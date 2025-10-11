eff TodoStorage {
    def getAllTodos(): List[Todo]
    def saveTodos(todos: List[Todo]): Unit
}

mod TodoStorageHandler {
    pub def runWithState(stateRef: Ref[List[Todo], r], f: Unit -> a \ ef): a \ ef - {TodoStorage} + r =
        run {
            f()
        } with handler TodoStorage {
            def getAllTodos(_, resume) = 
                let todos = Ref.get(stateRef);
                resume(todos)
            
            def saveTodos(todos, resume) = {
                Ref.put(todos, stateRef);
                resume()
            }
        }
}

enum TodoId with Eq, Order, ToString {
    case TodoId(String)
}

enum TodoText with Eq, ToString {
    case TodoText(String)
}

enum TodoStatus with Eq, ToString {
    case Active,
    case Completed
}

enum Todo with Eq, ToString {
    case Todo(TodoId, TodoText, TodoStatus)
}

mod Todo {
    
    pub def create(id: TodoId, text: TodoText): Todo = 
        Todo(id, text, TodoStatus.Active)
    
    pub def getId(todo: Todo): TodoId = 
        let Todo(id, _, _) = todo;
        id
    
    pub def getText(todo: Todo): TodoText = 
        let Todo(_, text, _) = todo;
        text
    
    pub def getStatus(todo: Todo): TodoStatus = 
        let Todo(_, _, status) = todo;
        status
    
    pub def isCompleted(todo: Todo): Bool = 
        getStatus(todo) == TodoStatus.Completed
    
    pub def toggle(todo: Todo): Todo = 
        let Todo(id, text, status) = todo;
        let newStatus = match status {
            case TodoStatus.Active => TodoStatus.Completed
            case TodoStatus.Completed => TodoStatus.Active
        };
        Todo(id, text, newStatus)
    
    pub def complete(todo: Todo): Todo = 
        let Todo(id, text, _) = todo;
        Todo(id, text, TodoStatus.Completed)
    
    pub def activate(todo: Todo): Todo = 
        let Todo(id, text, _) = todo;
        Todo(id, text, TodoStatus.Active)
}

mod TodoService {
    import java.util.UUID;
    
    pub def addTodo(text: String, todos: List[Todo]): Result[TodoError, (Todo, List[Todo])] \ IO =
        forM(
            validText <- TodoValidation.validateText(text) |> Result.mapErr(TodoError.ValidationError);
            newId <- generateUniqueId(todos)
        ) yield {
            let newTodo = Todo.create(newId, validText);
            (newTodo, newTodo :: todos)
        }
    
    pub def updateTodo(idStr: String, updateFn: Todo -> Todo, todos: List[Todo]): Result[TodoError, (Option[Todo], List[Todo])] =
        match TodoValidation.validateId(idStr) {
            case Ok(validId) => Ok(updateTodoInList(validId, updateFn, todos))
            case Err(e) => Err(TodoError.ValidationError(e))
        }

    pub def deleteTodo(idStr: String, todos: List[Todo]): Result[TodoError, List[Todo]] =
        match TodoValidation.validateId(idStr) {
            case Ok(validId) => 
                let filtered = List.filter(todo -> Todo.getId(todo) != validId, todos);
                if (List.length(filtered) == List.length(todos))
                    Err(TodoError.TodoNotFound(validId))
                else
                    Ok(filtered)
            case Err(e) => Err(TodoError.ValidationError(e))
        }

    pub def findTodo(idStr: String, todos: List[Todo]): Result[TodoError, Todo] =
        match TodoValidation.validateId(idStr) {
            case Ok(validId) => 
                match List.find(todo -> Todo.getId(todo) == validId, todos) {
                    case Some(todo) => Ok(todo)
                    case None => Err(TodoError.TodoNotFound(validId))
                }
            case Err(e) => Err(TodoError.ValidationError(e))
        }
    
    pub def getActiveTodos(todos: List[Todo]): List[Todo] =
        List.filter(todo -> not Todo.isCompleted(todo), todos)
    
    pub def getCompletedTodos(todos: List[Todo]): List[Todo] =
        List.filter(Todo.isCompleted, todos)
    
    def generateUniqueId(todos: List[Todo]): Result[TodoError, TodoId] \ IO =
        let existingIds = List.map(Todo.getId, todos) |> List.toSet;
        let newId = generateId();
        if (Set.memberOf(newId, existingIds))
            generateUniqueId(todos) // Retry if collision
        else
            Ok(newId)
    
    def generateId(): TodoId \ IO =  // Add IO effect
        let uuid = UUID.randomUUID();
        TodoId.TodoId(uuid.toString())
    
    def updateTodoInList(targetId: TodoId, updateFn: Todo -> Todo, todos: List[Todo]): (Option[Todo], List[Todo]) =
        def helper(remaining, updated, acc) = match remaining {
            case Nil => (updated, List.reverse(acc))
            case todo :: rest => 
                if (Todo.getId(todo) == targetId) {
                    let updatedTodo = updateFn(todo);
                    helper(rest, Some(updatedTodo), updatedTodo :: acc)
                } else {
                    helper(rest, updated, todo :: acc)
                }
        };
        helper(todos, None, Nil)
}

mod TodoValidation {
    pub def validateText(text: String): Result[ValidationError, TodoText] =
        let trimmed = String.trim(text);
        if (String.isEmpty(trimmed))
            Err(ValidationError.EmptyText)
        else if (String.length(trimmed) > 500)
            Err(ValidationError.TextTooLong(String.length(trimmed)))
        else if (containsInvalidChars(trimmed))
            Err(ValidationError.TextContainsInvalidChars)
        else
            Ok(TodoText.TodoText(trimmed))
    
    pub def validateId(id: String): Result[ValidationError, TodoId] =
        let trimmed = String.trim(id);
        if (String.isEmpty(trimmed))
            Err(ValidationError.InvalidId(id))
        else if (not isValidIdFormat(trimmed))
            Err(ValidationError.InvalidId(id))
        else
            Ok(TodoId.TodoId(trimmed))
    
    def containsInvalidChars(text: String): Bool =
        String.contains(substr="<", text) or 
        String.contains(substr=">", text) or
        String.contains(substr="&", text)
    
    def isValidIdFormat(id: String): Bool =
        String.forAll(c -> Char.isLetterOrDigit(c) or c == '-', id)
}

enum TodoError with Eq {
    case ValidationError(ValidationError),
    case TodoNotFound(TodoId),
    case DuplicateTodo(TodoId),
    case StorageError(String)
}

enum ValidationError with Eq {
    case EmptyText,
    case TextTooLong(Int32),
    case TextContainsInvalidChars,
    case InvalidId(String)
}

instance ToString[ValidationError] {
    pub def toString(e: ValidationError): String = match e {
        case ValidationError.EmptyText => 
            "Please enter some text for your todo item."
        case ValidationError.TextTooLong(len) => 
            "Todo text is too long (${len} characters). Please keep it under 500 characters."
        case ValidationError.TextContainsInvalidChars => 
            "Todo text contains invalid characters. Please avoid using <, >, and & symbols."
        case ValidationError.InvalidId(id) => 
            "Invalid todo ID: ${id}"
    }
}

instance ToString[TodoError] {
    pub def toString(e: TodoError): String = match e {
        case TodoError.ValidationError(ve) => 
            ToString.toString(ve)
        case TodoError.TodoNotFound(TodoId.TodoId(id)) => 
            "Todo item with ID '${id}' was not found."
        case TodoError.DuplicateTodo(TodoId.TodoId(id)) => 
            "A todo item with ID '${id}' already exists."
        case TodoError.StorageError(msg) => 
            "Storage error: ${msg}"
    }
}

instance Json.ToJson[Todo] {
    pub def toJson(todo: Todo): Json.JsonElement = {
        let Todo.Todo(id, text, status) = todo;
        let TodoId.TodoId(idStr) = id;
        let TodoText.TodoText(textStr) = text;
        let statusStr = match status {
            case TodoStatus.Active => "active"
            case TodoStatus.Completed => "completed"
        };
        
        Json.ToJson.toJson(Map#{
            "id" => idStr,
            "text" => textStr,
            "status" => statusStr
        })
    }
}
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
    let initialTodos = List#{
        Todo.create(TodoId.TodoId("demo-1"), TodoText.TodoText("Learn effect-oriented programming")),
        Todo.create(TodoId.TodoId("demo-2"), TodoText.TodoText("Build a todo app")),  
        Todo.create(TodoId.TodoId("demo-3"), TodoText.TodoText("Master HTMX integration"))
    };
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