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
def main(): Unit \ IO = {
    let routes = List#{
        Route.get("/hello", _ -> Response.ok("Hello, World!")),
        Route.get("/hello/{name}", req -> {
            let Request.Request(r) = req;
            match Map.get("name", r#pathParams) {
                case Some(name) => Response.ok("Hello, ${name}!")
                case None => Response.badRequest("Missing name")
            }
        })
    };

    Server.serve(8080, routes)
}
```

The framework provides:

- **Route definition** - `Route.get`, `Route.post`, `Route.put`, `Route.delete`, `Route.patch`
- **Request handling** - Access to path params, query params, and request body
- **Response building** - `Response.ok`, `Response.created`, `Response.notFound`, etc.
- **JSON support** - `Json.encode` and `Json.decode` with type class instances
- **OpenAPI generation** - Add metadata to routes for automatic API documentation

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
