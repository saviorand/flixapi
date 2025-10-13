///
/// Simple Todo API Example
///
/// This example demonstrates how to use the REST API framework
/// with effect-oriented programming in Flix.
///

///
/// Todo domain model
///
pub enum Todo {
    case Todo({ id = Int32, text = String, completed = Bool })
}

instance Eq[Todo] {
    pub def eq(t1: Todo, t2: Todo): Bool = 
        let Todo.Todo(r1) = t1;
        let Todo.Todo(r2) = t2;
        r1#id == r2#id
}

///
/// JSON serialization for Todo
///
instance Json.ToJson[Todo] {
    pub def toJson(todo: Todo): Json.JsonElement = {
        use Json.JsonElement.{JsonObject, JsonNumber, JsonString, JsonBool};
        let Todo.Todo(t) = todo;
        JsonObject(Map#{
            "id" => JsonNumber(Int32.toBigDecimal(t#id)),
            "text" => JsonString(t#text),
            "completed" => JsonBool(t#completed)
        })
    }
}

instance Json.FromJson[Todo] {
    pub def fromJsonAt(p: Json.Path.Path, json: Json.JsonElement): Result[Json.JsonError, Todo] = {
        forM (
            obj <- Json.FromJson.fromJsonAt(p, json);
            id <- Json.getAtKey(p, "id", obj);
            text <- Json.getAtKey(p, "text", obj);
            completed <- Json.getAtKey(p, "completed", obj)
        ) yield Todo.Todo({ id = id, text = text, completed = completed })
    }
}

///
/// TodoStore effect for managing todo state
///
eff TodoStore {
    /// Get all todos
    def getAll(): List[Todo]
    
    /// Get a todo by ID
    def getById(id: Int32): Option[Todo]
    
    /// Add a new todo
    def add(text: String): Todo
    
    /// Delete a todo by ID
    def delete(id: Int32): Bool
}

///
/// Opaque state wrapper for todos
///
enum TodoState[r: Region] {
    case TodoState(Ref[List[Todo], r])
}

///
/// TodoStore effect handler using region-based state
///
mod TodoStore {
    ///
    /// Handles the TodoStore effect with region-based state, interpreting it as IO
    ///
    pub def runWithState(stateRef: Ref[List[Todo], r], f: Unit -> a \ ef): a \ ef - TodoStore + {IO, r} = {
        run {
            f()
        } with handler TodoStore {
            def getAll(resume) = 
                Ref.get(stateRef) |> resume
            
            def getById(id, resume) = {
                let todos = Ref.get(stateRef);
                List.find(match Todo.Todo(t) -> t#id == id, todos) |> resume
            }
            
            def add(text, resume) = {
                let todos = Ref.get(stateRef);
                let newId = List.length(todos) + 1;
                let newTodo = Todo.Todo({ id = newId, text = text, completed = false });
                Ref.put(newTodo :: todos, stateRef);
                resume(newTodo)
            }
            
            def delete(id, resume) = {
                let todos = Ref.get(stateRef);
                let filtered = List.filter(match Todo.Todo(t) -> t#id != id, todos);
                let wasDeleted = List.length(filtered) != List.length(todos);
                Ref.put(filtered, stateRef);
                resume(wasDeleted)
            }
        }
    }
}

///
/// API Handlers using TodoStore effect
///
mod Handlers {
    ///
    /// Get all todos
    ///
    pub def getAllTodos(_req: Request): Response \ TodoStore = {
        let todos = TodoStore.getAll();
        Response.ok(Json.encode(todos))
    }
    
    ///
    /// Get a single todo by ID
    ///
    pub def getTodo(req: Request): Response \ TodoStore = {
        let Request.Request(r) = req;
        match Map.get("id", r#pathParams) {
            case None => Response.badRequest("Missing id parameter")
            case Some(idStr) => 
                match Int32.fromString(idStr) {
                    case None => Response.badRequest("Invalid id format")
                    case Some(id) =>
                        match TodoStore.getById(id) {
                            case None => Response.notFound("Todo not found")
                            case Some(todo) => Response.ok(Json.encode(todo))
                        }
                }
        }
    }
    
    ///
    /// Create a new todo (expects JSON with "text" field)
    ///
    pub def createTodo(req: Request): Response \ TodoStore = {
        let Request.Request(r) = req;
        match r#body {
            case None => Response.badRequest("Request body required")
            case Some(body) => {
                let objOpt: Option[Map[String, String]] = Json.decode(body);
                match objOpt {
                    case None => Response.badRequest("Invalid JSON")
                    case Some(obj) =>
                        match Map.get("text", obj) {
                            case None => Response.badRequest("Missing 'text' field")
                            case Some(text) => 
                                let newTodo = TodoStore.add(text);
                                Response.created(Json.encode(newTodo))
                        }
                }
            }
        }
    }
    
    ///
    /// Delete a todo by ID
    ///
    pub def deleteTodo(req: Request): Response \ TodoStore = {
        let Request.Request(r) = req;
        match Map.get("id", r#pathParams) {
            case None => Response.badRequest("Missing id parameter")
            case Some(idStr) => 
                match Int32.fromString(idStr) {
                    case None => Response.badRequest("Invalid id format")
                    case Some(id) =>
                        if (TodoStore.delete(id))
                            Response.noContent()
                        else
                            Response.notFound("Todo not found")
                }
        }
    }
}

///
/// Main entry point
///
def main(): Unit \ IO = region rc {
    // Initialize with some sample todos
    let initialTodos = List#{
        Todo.Todo({ id = 1, text = "Learn Flix", completed = false }),
        Todo.Todo({ id = 2, text = "Build a REST API", completed = true })
    };
    let stateRef = Ref.fresh(rc, initialTodos);
    
    // Define routes - handlers are interpreted with TodoStore effect handler
    let routes = List#{
        Route.get("/todos", req -> 
            run { Handlers.getAllTodos(req) } with TodoStore.runWithState(stateRef)),
        
        Route.get("/todos/{id}", req -> 
            run { Handlers.getTodo(req) } with TodoStore.runWithState(stateRef)),
        
        Route.post("/todos", req -> 
            run { Handlers.createTodo(req) } with TodoStore.runWithState(stateRef)),
        
        Route.delete("/todos/{id}", req -> 
            run { Handlers.deleteTodo(req) } with TodoStore.runWithState(stateRef))
    };
    
    Server.serve(8080, routes)
}