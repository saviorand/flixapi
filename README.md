# FlixAPI

A REST API framework for Flix with effect-oriented programming.

## Features

- Type-safe routing with path and query parameters
- JSON serialization/deserialization
- OpenAPI 3.0 specification generation
- Interactive API documentation with Scalar UI
- Effect-polymorphic handlers

## Quick Start

```flix
def main(): Unit \ IO = region rc {
    let stateRef = Ref.fresh(rc, initialState);

    let routes = List#{
        Route.get("/todos", req -> Handlers.getAllTodos(req)),
        Route.post("/todos", req -> Handlers.createTodo(req))
    };

    Server.serve(8080, routes)
}
```

## Examples

See [examples/todo/](examples/todo/) for a complete Todo API demonstrating:
- Custom effects with effect handlers
- CRUD operations
- OpenAPI documentation
- State management with regions

Run the example:

```bash
cd examples/todo
java -jar ../../flix.jar run
```

Server starts at `http://localhost:8080` with API docs at `/api/docs`.

## License

See LICENSE.md
