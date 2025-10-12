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
/// Opaque state wrapper for todos
///
pub enum TodoState[r: Region] {
    case TodoState(Ref[List[Todo], r])
}

///
/// State management operations
///
mod TodoState {
    ///
    /// Create a new state with initial todos
    ///
    pub def mkState(rc: Region[r], initial: List[Todo]): TodoState[r] \ r = {
        let stateRef = Ref.fresh(rc, initial);
        TodoState.TodoState(stateRef)
    }
    
    ///
    /// Get all todos
    ///
    pub def getAll(state: TodoState[r]): List[Todo] \ r = {
        let TodoState.TodoState(stateRef) = state;
        Ref.get(stateRef)
    }
    
    ///
    /// Get a todo by ID
    ///
    pub def getById(id: Int32, state: TodoState[r]): Option[Todo] \ r = {
        let todos = getAll(state);
        List.find(match Todo.Todo(t) -> t#id == id, todos)
    }
    
    ///
    /// Add a new todo
    ///
    pub def add(text: String, state: TodoState[r]): Todo \ r = {
        let TodoState.TodoState(stateRef) = state;
        let todos = Ref.get(stateRef);
        let newId = List.length(todos) + 1;
        let newTodo = Todo.Todo({ id = newId, text = text, completed = false });
        Ref.put(newTodo :: todos, stateRef);
        newTodo
    }
    
    ///
    /// Delete a todo by ID
    ///
    pub def delete(id: Int32, state: TodoState[r]): Bool \ r = {
        let TodoState.TodoState(stateRef) = state;
        let todos = Ref.get(stateRef);
        let filtered = List.filter(match Todo.Todo(t) -> t#id != id, todos);
        let wasDeleted = List.length(filtered) != List.length(todos);
        Ref.put(filtered, stateRef);
        wasDeleted
    }
}

///
/// API Handlers
///
mod Handlers {
    ///
    /// Get all todos
    ///
    pub def getAllTodos(state: TodoState[r], _req: Request): Response \ r = {
        let todos = TodoState.getAll(state);
        Response.ok(Json.encode(todos))
    }
    
    ///
    /// Get a single todo by ID
    ///
    pub def getTodo(state: TodoState[r], req: Request): Response \ r = {
        let Request.Request(r) = req;
        match Map.get("id", r#pathParams) {
            case None => Response.badRequest("Missing id parameter")
            case Some(idStr) => 
                match Int32.fromString(idStr) {
                    case None => Response.badRequest("Invalid id format")
                    case Some(id) =>
                        match TodoState.getById(id, state) {
                            case None => Response.notFound("Todo not found")
                            case Some(todo) => Response.ok(Json.encode(todo))
                        }
                }
        }
    }
    
    ///
    /// Create a new todo (expects JSON with "text" field)
    ///
    pub def createTodo(state: TodoState[r], req: Request): Response \ r = {
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
                                let newTodo = TodoState.add(text, state);
                                Response.created(Json.encode(newTodo))
                        }
                }
            }
        }
    }
    
    ///
    /// Delete a todo by ID
    ///
    pub def deleteTodo(state: TodoState[r], req: Request): Response \ r = {
        let Request.Request(r) = req;
        match Map.get("id", r#pathParams) {
            case None => Response.badRequest("Missing id parameter")
            case Some(idStr) => 
                match Int32.fromString(idStr) {
                    case None => Response.badRequest("Invalid id format")
                    case Some(id) =>
                        if (TodoState.delete(id, state))
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
    let state = TodoState.mkState(rc, initialTodos);
    
    // Define routes - casting region effect to IO for long-lived server state
    let routes = List#{
        Route.get("/todos", req -> unchecked_cast(Handlers.getAllTodos(state, req) as _ \ IO)),
        Route.get("/todos/{id}", req -> unchecked_cast(Handlers.getTodo(state, req) as _ \ IO)),
        Route.post("/todos", req -> unchecked_cast(Handlers.createTodo(state, req) as _ \ IO)),
        Route.delete("/todos/{id}", req -> unchecked_cast(Handlers.deleteTodo(state, req) as _ \ IO))
    };
    
    Server.serve(8080, routes)
}