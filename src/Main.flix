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
    /// Handler: Get all todos
    ///
    pub def getAllTodos(_params: Map[String, String]): Result[RestApi.ApiError, List[Todo]] \ {TodoStorage, IO} = {
        println("Fetching all todos");
        let todos = TodoStorage.getAllTodos();
        println("Fetched todos: ${todos}");
        Ok(todos)
    }
    
    ///
    /// Handler: Get todo by ID
    ///
    pub def getTodoById(params: Map[String, String]): Result[RestApi.ApiError, Todo] \ {TodoStorage, IO} = {
        let id = Map.getWithDefault("id", "", params);
        println("Fetching todo with id: ${id}");
        match TodoService.findTodo(id, TodoStorage.getAllTodos()) {
            case Ok(todo) => Ok(todo)
            case Err(_) => Err(RestApi.ApiError.NotFound("Todo not found"))
        }
    }
    
    ///
    /// Handler: Create a new todo
    ///
    pub def createTodo(req: CreateTodoRequest): Result[RestApi.ApiError, Todo] \ {TodoStorage, IO} = {
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
    
    ///
    /// Handler: Delete todo by ID
    ///
    pub def deleteTodoById(params: Map[String, String]): Result[RestApi.ApiError, String] \ {TodoStorage, IO} = {
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
}

///
/// Main entry point
///
def main(): Unit \ IO = region rc {
    let initialTodos = AppConfig.getInitialTodos(AppConfig.webApp(8080));
    let stateRef = Ref.fresh(rc, initialTodos);
    
    // Helper function to wrap route handlers with effect handlers
    def withEffects(routeHandler) = (params, queryParams, bodyOpt) -> {
        run {
            routeHandler(params, queryParams, bodyOpt)
        } with TodoStorageHandler.runWithState(stateRef)
    };
    
    // Define routes with effects applied
    let routes = List#{
        RestApi.get("/todos", 
            withEffects(RestApi.Json.jsonHandler(TodoApi.getAllTodos))),
        
        RestApi.get("/todos/{id}", 
            withEffects(RestApi.Json.jsonHandler(TodoApi.getTodoById))),
        
        RestApi.post("/todos", 
            withEffects(RestApi.Json.jsonBodyHandler(TodoApi.createTodo))),
        
        RestApi.delete("/todos/{id}", 
            withEffects(RestApi.Json.jsonHandler(TodoApi.deleteTodoById)))
    };
    
    RestApi.Server.serve(8080, routes)
}