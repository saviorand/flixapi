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
    
    /// Update an existing todo
    def update(id: Int32, text: String, completed: Bool): Option[Todo]
    
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
            
            def update(id, text, completed, resume) = {
                let todos = Ref.get(stateRef);
                let updatedTodos = List.map(match Todo.Todo(t) -> 
                    if (t#id == id)
                        Todo.Todo({ id = id, text = text, completed = completed })
                    else
                        Todo.Todo(t)
                , todos);
                let found = List.find(match Todo.Todo(t) -> t#id == id, todos);
                match found {
                    case Some(_) => {
                        Ref.put(updatedTodos, stateRef);
                        resume(Some(Todo.Todo({ id = id, text = text, completed = completed })))
                    }
                    case None => resume(None)
                }
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
    /// Update a todo by ID
    ///
    pub def updateTodo(req: Request): Response \ TodoStore = {
        let Request.Request(r) = req;
        match Map.get("id", r#pathParams) {
            case None => Response.badRequest("Missing id parameter")
            case Some(idStr) => 
                match Int32.fromString(idStr) {
                    case None => Response.badRequest("Invalid id format")
                    case Some(id) =>
                        match r#body {
                            case None => Response.badRequest("Request body required")
                            case Some(body) => {
                                let todoOpt: Option[Todo] = Json.decode(body);
                                match todoOpt {
                                    case None => Response.badRequest("Invalid JSON")
                                    case Some(Todo.Todo(t)) => {
                                        match TodoStore.update(id, t#text, t#completed) {
                                            case None => Response.notFound("Todo not found")
                                            case Some(updated) => Response.ok(Json.encode(updated))
                                        }
                                    }
                                }
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
/// Define schemas for OpenAPI documentation
///
mod Schemas {
    use OpenApi.Schema
    use OpenApi.Schema.{ObjectSchema, ArraySchema, StringSchema, IntegerSchema, BooleanSchema, RefSchema}
    use OpenApi.NamedSchema
    use OpenApi.NamedSchema.NamedSchema
    
    ///
    /// Schema for a single Todo item (inline definition)
    ///
    def todoSchemaDefinition(): Schema = 
        ObjectSchema(Map#{
            "id" => IntegerSchema,
            "text" => StringSchema,
            "completed" => BooleanSchema
        })
    
    ///
    /// Schema for creating a new Todo (no id field, inline definition)
    ///
    def createTodoSchemaDefinition(): Schema = 
        ObjectSchema(Map#{
            "text" => StringSchema
        })
    
    ///
    /// Reference to the Todo schema
    ///
    pub def todoRef(): Schema = RefSchema("Todo")
    
    ///
    /// Reference to an array of Todos
    ///
    pub def todoListRef(): Schema = ArraySchema(RefSchema("Todo"))
    
    ///
    /// Reference to the CreateTodo schema
    ///
    pub def createTodoRef(): Schema = RefSchema("CreateTodo")
    
    ///
    /// All named schemas for the components section
    ///
    pub def allSchemas(): List[NamedSchema] = 
        List#{
            NamedSchema({ name = "Todo", schema = todoSchemaDefinition() }),
            NamedSchema({ name = "CreateTodo", schema = createTodoSchemaDefinition() })
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
    
    // Define routes with OpenAPI metadata
    let routes = List#{
        Route.get("/todos", req -> 
            run { Handlers.getAllTodos(req) } with TodoStore.runWithState(stateRef))
            |> Route.withMetadata(
                RouteMetadata.empty()
                |> RouteMetadata.withSummary("Get all todos")
                |> RouteMetadata.withDescription("Retrieves a list of all todo items")
                |> RouteMetadata.withTags("todos" :: Nil)
                |> RouteMetadata.withResponse("List of todo items")
                |> RouteMetadata.withResponseSchema(Schemas.todoListRef())
            ),
        
        Route.get("/todos/{id}", req -> 
            run { Handlers.getTodo(req) } with TodoStore.runWithState(stateRef))
            |> Route.withMetadata(
                RouteMetadata.empty()
                |> RouteMetadata.withSummary("Get a todo by ID")
                |> RouteMetadata.withDescription("Retrieves a single todo item by its ID")
                |> RouteMetadata.withTags("todos" :: Nil)
                |> RouteMetadata.withResponse("The requested todo item")
                |> RouteMetadata.withResponseSchema(Schemas.todoRef())
            ),
        
        Route.post("/todos", req -> 
            run { Handlers.createTodo(req) } with TodoStore.runWithState(stateRef))
            |> Route.withMetadata(
                RouteMetadata.empty()
                |> RouteMetadata.withSummary("Create a new todo")
                |> RouteMetadata.withDescription("Creates a new todo item with the provided text")
                |> RouteMetadata.withTags("todos" :: Nil)
                |> RouteMetadata.withRequestBody("Todo item with 'text' field")
                |> RouteMetadata.withRequestSchema(Schemas.createTodoRef())
                |> RouteMetadata.withResponse("The created todo item")
                |> RouteMetadata.withResponseSchema(Schemas.todoRef())
            ),
        
        Route.put("/todos/{id}", req -> 
            run { Handlers.updateTodo(req) } with TodoStore.runWithState(stateRef))
            |> Route.withMetadata(
                RouteMetadata.empty()
                |> RouteMetadata.withSummary("Update a todo")
                |> RouteMetadata.withDescription("Updates an existing todo item with new text and/or completion status")
                |> RouteMetadata.withTags("todos" :: Nil)
                |> RouteMetadata.withRequestBody("Updated todo item")
                |> RouteMetadata.withRequestSchema(Schemas.todoRef())
                |> RouteMetadata.withResponse("The updated todo item")
                |> RouteMetadata.withResponseSchema(Schemas.todoRef())
            ),
        
        Route.delete("/todos/{id}", req -> 
            run { Handlers.deleteTodo(req) } with TodoStore.runWithState(stateRef))
            |> Route.withMetadata(
                RouteMetadata.empty()
                |> RouteMetadata.withSummary("Delete a todo")
                |> RouteMetadata.withDescription("Deletes a todo item by its ID")
                |> RouteMetadata.withTags("todos" :: Nil)
                |> RouteMetadata.withResponse("No content on successful deletion")
            )
    };
    
    // Create API info for OpenAPI spec
    let apiInfo = OpenApi.ApiInfo.ApiInfo({
        title = "Todo API",
        version = "1.0.0",
        description = Some("A simple REST API for managing todo items built with Flix")
    });
    
    // Configure CORS based on your environment:
    // 
    // Development (allow all origins):
    let corsConfig = CorsConfig.AllowAll;
    // 
    // Production (allow specific origins only):
    // let corsConfig = CorsConfig.AllowOrigins(List#{"https://yourdomain.com", "https://app.yourdomain.com"});
    // 
    // Disable CORS (no headers):
    // let corsConfig = CorsConfig.Disabled;
    
    println("Starting Todo API server...");
    println("API Documentation available at: http://localhost:8080/api/docs");
    println("OpenAPI spec available at: http://localhost:8080/openapi.json");
    
    // Serve with automatic API documentation and named schemas
    OpenApi.serveWithDocsAndSchemas(8080, corsConfig, apiInfo, routes, Schemas.allSchemas())
}