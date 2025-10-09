///
/// Todo API using RestApi framework
///
mod TodoApi {
    use RestApi.{Api, Route}
    use RestApi.Json.{jsonHandler, jsonBodyHandler}
    use Json.JsonElement
    use Json.ToJson
    use Json.FromJson
    use Json.Path.Path
    
    ///
    /// JSON deserialization for creating todos
    ///
    pub enum CreateTodoRequest {
        case CreateTodoRequest(String)
    }
    
    instance FromJson[CreateTodoRequest] {
        pub def fromJsonAt(p: Path, json: JsonElement): Result[Json.JsonError, CreateTodoRequest] = {
            forM (
                obj <- FromJson.fromJsonAt(p, json);
                text <- Json.getAtKey(p, "text", obj)
            ) yield CreateTodoRequest.CreateTodoRequest(text)
        }
    }
    
    ///
    /// Define API routes
    ///
    pub def routes(): List[Route[{TodoStorage, IO}]] = List#{
        // GET /todos - List all todos
        RestApi.get("/todos", jsonHandler(getAllTodos)),
        
        // GET /todos/{id} - Get specific todo
        RestApi.get("/todos/{id}", jsonHandler(getTodoById)),
        
        // POST /todos - Create new todo
        RestApi.post("/todos", jsonBodyHandler(createTodo)),
        
        // DELETE /todos/{id} - Delete todo
        RestApi.delete("/todos/{id}", jsonHandler(deleteTodoById))
    }
    
    ///
    /// Handler functions - all with {TodoStorage, IO} effect
    ///
    def getAllTodos(_params: Map[String, String]): Result[RestApi.ApiError, List[Todo]] \ {TodoStorage, IO} = {
        let todos = TodoStorage.getAllTodos();
        println("Fetched todos: ${todos}");
        Ok(todos)
    }
    
    def getTodoById(params: Map[String, String]): Result[RestApi.ApiError, Todo] \ {TodoStorage, IO} = {
        let id = Map.getWithDefault("id", "", params);
        println("Fetching todo with id: ${id}");
        match TodoService.findTodo(id, TodoStorage.getAllTodos()) {
            case Ok(todo) => Ok(todo)
            case Err(_) => Err(RestApi.ApiError.NotFound("Todo not found"))
        }
    }
    
    def createTodo(req: CreateTodoRequest): Result[RestApi.ApiError, Todo] \ {TodoStorage, IO} = {
        let CreateTodoRequest.CreateTodoRequest(text) = req;
        let todos = TodoStorage.getAllTodos();
        match TodoService.addTodo(text, todos) {
            case Ok((newTodo, updatedTodos)) => {
                TodoStorage.saveTodos(updatedTodos);
                Ok(newTodo)
            }
            case Err(err) => 
                Err(RestApi.ApiError.BadRequest(ToString.toString(err)))
        }
    }
    
    def deleteTodoById(params: Map[String, String]): Result[RestApi.ApiError, String] \ {TodoStorage, IO} = {
        let id = Map.getWithDefault("id", "", params);
        let todos = TodoStorage.getAllTodos();
        println("Deleting todo with id: ${id}");
        match TodoService.deleteTodo(id, todos) {
            case Ok(updatedTodos) => {
                TodoStorage.saveTodos(updatedTodos);
                Ok("Deleted")
            }
            case Err(_) => 
                Err(RestApi.ApiError.NotFound("Todo not found"))
        }
    }
    
    ///
    /// Create API configuration
    ///
    pub def api(): Api[{TodoStorage, IO}] = {
        RestApi.Api.Api({
            title = "Todo API",
            version = "1.0.0",
            description = "A simple todo list API built with Flix",
            routes = routes()
        })
    }
}

///
/// Main entry point
///
def main(): Unit \ IO = region rc {
    let initialTodos = AppConfig.getInitialTodos(AppConfig.webApp(8080));
    let stateRef = Ref.fresh(rc, initialTodos);
    
    run {
        RestApi.Server.serve(8080, TodoApi.api())
    } with TodoStorageHandler.runWithState(stateRef)
}