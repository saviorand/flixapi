# FlixAPI - Effect-Oriented REST API Framework for Flix

A simple, well-designed REST API framework for Flix that embraces effect-oriented programming.

## Features

- **Simple & Idiomatic**: Follows Flix best practices and idiomatic patterns
- **Type-Safe**: Full type safety with Flix's powerful type system
- **Effect-Oriented**: Clean separation of effects using Flix's effect system
- **JSON Support**: Built-in JSON serialization/deserialization using flix-json
- **Minimal Dependencies**: Uses Java's built-in HTTP server for simplicity

## Framework Design

The framework is organized into three main modules:

### Core Types

- **`Method`**: HTTP methods (Get, Post, Put, Delete, Patch)
- **`Status`**: HTTP status codes (Ok, Created, NotFound, etc.)
- **`Request`**: HTTP request with path parameters, query parameters, and body
- **`Response`**: HTTP response with status and body
- **`Route`**: Route definition mapping paths to handlers

### JSON Module

Helper functions for working with JSON:

- `encode`: Serialize a value to JSON string
- `decode`: Parse JSON string to a value
- `get`: Lift a function returning JSON to a handler
- `post`: Lift a function accepting/returning JSON to a handler

### Server Module

HTTP server implementation:

- `serve`: Start the server on a given port with routes
- Path parameter extraction (e.g., `/todos/{id}`)
- Query parameter parsing
- Request body handling

## Example Usage

```flix
def main(): Unit \ IO = {
    // Define your state
    let state = TodoState.mkState(initialTodos);
    
    // Define routes
    let routes = List#{
        Route.get("/todos", req -> Handlers.getAllTodos(state, req)),
        Route.get("/todos/{id}", req -> Handlers.getTodo(state, req)),
        Route.post("/todos", req -> Handlers.createTodo(state, req)),
        Route.delete("/todos/{id}", req -> Handlers.deleteTodo(state, req))
    };
    
    // Start the server
    Server.serve(8080, routes)
}
```

## Handler Example

```flix
pub def getAllTodos(state: AtomicReference, _req: Request): Response \ IO = {
    let todos = TodoState.getAll(state);
    Response.ok(Json.encode(todos))
}
```

## Running the Example

```bash
java -jar flix.jar run
```

The server will start on `http://localhost:8080` with the following endpoints:

- `GET /todos` - Get all todos
- `GET /todos/{id}` - Get a specific todo
- `POST /todos` - Create a new todo (expects `{"text": "..."}`)
- `DELETE /todos/{id}` - Delete a todo

## Testing with curl

```bash
# Get all todos
curl http://localhost:8080/todos

# Get a specific todo
curl http://localhost:8080/todos/1

# Create a new todo
curl -X POST http://localhost:8080/todos \
  -H "Content-Type: application/json" \
  -d '{"text": "Write documentation"}'

# Delete a todo
curl -X DELETE http://localhost:8080/todos/1
```

## Design Principles

1. **Simplicity**: The framework avoids unnecessary complexity
2. **Type Safety**: Leverages Flix's type system for compile-time guarantees
3. **Effect Tracking**: All effects are tracked through Flix's effect system
4. **Composability**: Handlers are just functions that can be easily composed
5. **Idiomatic Flix**: Follows patterns seen in the Flix standard library and examples

## Improvements Over Original

The rewritten framework features:

- Cleaner separation of concerns (types, JSON, server)
- Simpler handler types (`Request -> Response \ IO`)
- Better organized modules
- Removed unnecessary complexity (OpenAPI generation, complex error types)
- Simplified the todo example while keeping it functional
- More idiomatic Flix code following best practices

## Future Enhancements

Possible improvements for production use:

- Middleware support for cross-cutting concerns
- Better error handling with custom error types
- Async/concurrent request handling
- Request/response interceptors
- CORS support
- Static file serving
- Template rendering

## License

See LICENSE.md
