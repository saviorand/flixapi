///
/// RestApi - An effect-oriented REST API framework for Flix
///
/// This framework follows idiomatic Flix design patterns:
/// - Effects for HTTP requests and responses
/// - Clean separation of concerns
/// - Effect handlers for different runtime behaviors
///

///
/// HTTP methods
///
pub enum Method with Eq, ToString {
    case Get
    case Post  
    case Put
    case Delete
    case Patch
}

///
/// HTTP status codes
///
pub enum Status with Eq, ToString {
    case Ok
    case Created
    case NoContent
    case BadRequest
    case Unauthorized
    case NotFound
    case InternalError
}

mod Status {
    ///
    /// Convert status to HTTP status code
    ///
    pub def toCode(status: Status): Int32 = match status {
        case Status.Ok            => 200
        case Status.Created       => 201
        case Status.NoContent     => 204
        case Status.BadRequest    => 400
        case Status.Unauthorized  => 401
        case Status.NotFound      => 404
        case Status.InternalError => 500
    }
}

///
/// HTTP request information
///
pub enum Request {
    case Request({
        pathParams = Map[String, String],
        queryParams = Map[String, String],
        body = Option[String]
    })
}

///
/// HTTP response
///
pub enum Response {
    case Response({
        status = Status,
        body = String
    })
}

mod Response {
    ///
    /// Create a successful response with a body
    ///
    pub def ok(body: String): Response =
        Response.Response({ status = Status.Ok, body = body })
    
    ///
    /// Create a created response
    ///
    pub def created(body: String): Response =
        Response.Response({ status = Status.Created, body = body })
    
    ///
    /// Create a no content response
    ///
    pub def noContent(): Response =
        Response.Response({ status = Status.NoContent, body = "" })
    
    ///
    /// Create an error response
    ///
    pub def error(status: Status, message: String): Response =
        Response.Response({ status = status, body = message })
    
    ///
    /// Create a bad request response
    ///
    pub def badRequest(message: String): Response =
        error(Status.BadRequest, message)
    
    ///
    /// Create a not found response
    ///
    pub def notFound(message: String): Response =
        error(Status.NotFound, message)
}

///
/// Route metadata for OpenAPI documentation
///
pub enum RouteMetadata {
    case RouteMetadata({
        summary = Option[String],
        description = Option[String],
        tags = List[String],
        requestBodyDescription = Option[String],
        responseDescription = Option[String]
    })
}

mod RouteMetadata {
    ///
    /// Create empty metadata
    ///
    pub def empty(): RouteMetadata =
        RouteMetadata.RouteMetadata({
            summary = None,
            description = None,
            tags = Nil,
            requestBodyDescription = None,
            responseDescription = None
        })
    
    ///
    /// Add a summary to metadata
    ///
    pub def withSummary(summary: String, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({summary = Some(summary) | m})
    
    ///
    /// Add a description to metadata
    ///
    pub def withDescription(desc: String, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({description = Some(desc) | m})
    
    ///
    /// Add tags to metadata
    ///
    pub def withTags(tags: List[String], metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({tags = tags | m})
    
    ///
    /// Add request body description
    ///
    pub def withRequestBody(desc: String, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({requestBodyDescription = Some(desc) | m})
    
    ///
    /// Add response description
    ///
    pub def withResponse(desc: String, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({responseDescription = Some(desc) | m})
}

///
/// Route definition - effect polymorphic to support any handler effects
///
pub enum Route[ef: Eff] {
    case Route(Method, String, Request -> Response \ ef, RouteMetadata)
}

mod Route {
    ///
    /// Create a GET route
    ///
    pub def get(path: String, h: Request -> Response \ ef): Route[ef] =
        Route.Route(Method.Get, path, h, RouteMetadata.empty())
    
    ///
    /// Create a POST route
    ///
    pub def post(path: String, h: Request -> Response \ ef): Route[ef] =
        Route.Route(Method.Post, path, h, RouteMetadata.empty())
    
    ///
    /// Create a PUT route
    ///
    pub def put(path: String, h: Request -> Response \ ef): Route[ef] =
        Route.Route(Method.Put, path, h, RouteMetadata.empty())
    
    ///
    /// Create a DELETE route
    ///
    pub def delete(path: String, h: Request -> Response \ ef): Route[ef] =
        Route.Route(Method.Delete, path, h, RouteMetadata.empty())
    
    ///
    /// Add metadata to a route
    ///
    pub def withMetadata(metadata: RouteMetadata, route: Route[ef]): Route[ef] =
        let Route.Route(method, path, h, _) = route;
        Route.Route(method, path, h, metadata)
}

///
/// JSON helpers for REST API
///
mod Json {
    use Json.JsonElement
    use Json.ToJson
    use Json.FromJson
    
    ///
    /// Serialize a Flix value to JSON string
    ///
    pub def encode(x: a): String with ToJson[a] =
        ToJson.toJson(x) |> Json.Write.toCompactString
    
    ///
    /// Parse JSON string to Flix value
    ///
    pub def decode(s: String): Option[a] with FromJson[a] =
        match Json.Parse.parse(s) {
            case None => None
            case Some(elem) => 
                FromJson.fromJson(elem) |> Result.toOption
        }
    
    ///
    /// Create a JSON response handler for GET/DELETE routes
    ///
    pub def wrap(f: Request -> Response): Request -> Response =
        req -> f(req)
    
    ///
    /// Lift a function that returns a JSON-serializable value into a handler
    ///
    pub def get(f: Request -> a): Request -> Response with ToJson[a] =
        req -> {
            let result = f(req);
            Response.ok(encode(result))
        }
    
    ///
    /// Lift a function that accepts and returns JSON values into a POST handler
    ///
    pub def post(f: a -> b): Request -> Response with FromJson[a], ToJson[b] =
        req -> {
            let Request.Request(r) = req;
            match r#body {
                case None => Response.badRequest("Request body required")
                case Some(body) => 
                    match decode(body) {
                        case None => Response.badRequest("Invalid JSON in request body")
                        case Some(input) => 
                            let output = f(input);
                            Response.ok(encode(output))
                    }
            }
        }
}

///
/// HTTP Server integration
///
mod Server {
    import java.net.InetSocketAddress
    import java.lang.{Thread => JThread, InterruptedException}
    import com.sun.net.httpserver.{HttpServer => JavaHttpServer, HttpHandler, HttpExchange}
    import java.io.{BufferedReader, InputStreamReader}
    
    ///
    /// Start the REST API server
    ///
    pub def serve(port: Int32, routes: List[Route[ef]]): Unit \ IO = {
        let addr = new InetSocketAddress(port);
        let server = JavaHttpServer.create(addr, 0);
        
        // Group routes by base path for efficient routing
        let routesByBasePath = groupRoutesByBasePath(routes);
        Map.forEach((basePath, routesForPath) -> 
            registerRoutesAtPath(server, basePath, routesForPath), routesByBasePath);
        
        server.start();
        println("Server running on http://localhost:${port}");
        
        try {
            JThread.currentThread().join()
        } catch {
            case _: InterruptedException => 
                println("Server stopped")
        }
    }
    
    ///
    /// Group routes by their base path (without parameters)
    ///
    def groupRoutesByBasePath(routes: List[Route[ef]]): Map[String, List[Route[ef]]] = {
        List.foldLeft((acc, route) -> {
            let Route.Route(_, path, _, _) = route;
            let basePath = extractBasePath(path);
            let existing = Map.getWithDefault(basePath, Nil, acc);
            Map.insert(basePath, route :: existing, acc)
        }, Map.empty(), routes)
    }
    
    ///
    /// Extract base path from a pattern like "/todos/{id}" -> "/todos"
    ///
    def extractBasePath(pattern: String): String = {
        let parts = String.split(regex="/", pattern);
        let baseParts = List.takeWhile(part -> 
            not (String.startsWith(prefix="{", part) and String.endsWith(suffix="}", part)), 
            parts);
        String.intercalate("/", baseParts)
    }
    
    ///
    /// Register all routes at a given base path with a multiplexing handler
    ///
    def registerRoutesAtPath(server: JavaHttpServer, basePath: String, routes: List[Route[ef]]): Unit \ IO = {
        let javaHandler = new HttpHandler {
            def $handle(_this: HttpHandler, exchange: HttpExchange): Unit \ {IO, ef} = {
                let method = exchange.getRequestMethod();
                let path = exchange.getRequestURI().getPath();
                
                // Find matching route
                let matchingRoute = List.find(route -> {
                    let Route.Route(m, p, _, _) = route;
                    methodMatches(method, m) and pathMatches(p, path)
                }, routes);
                
                match matchingRoute {
                    case Some(Route.Route(_, pathPattern, h, _)) => {
                        let pathParams = extractPathParams(pathPattern, path);
                        let queryParams = extractQueryParams(exchange);
                        let body = readRequestBody(exchange);
                        
                        let request = Request.Request({
                            pathParams = pathParams,
                            queryParams = queryParams,
                            body = body
                        });
                        
                        let response = h(request);
                        let Response.Response(r) = response;
                        
                        // Check if response is HTML
                        if (String.startsWith(prefix="<!DOCTYPE html>", r#body) or String.startsWith(prefix="<html>", r#body))
                            writeHtmlResponse(exchange, r#body)
                        else
                            writeResponse(exchange, response)
                    }
                    case None =>
                        let notFoundResp = Response.notFound("Route not found");
                        writeResponse(exchange, notFoundResp)
                }
            }
        };
        discard server.createContext(basePath, javaHandler);
        ()
    }
    
    ///
    /// Check if HTTP method matches
    ///
    def methodMatches(httpMethod: String, apiMethod: Method): Bool =
        match apiMethod {
            case Method.Get    => httpMethod == "GET"
            case Method.Post   => httpMethod == "POST"  
            case Method.Put    => httpMethod == "PUT"
            case Method.Delete => httpMethod == "DELETE"
            case Method.Patch  => httpMethod == "PATCH"
        }
    
    ///
    /// Check if a path matches a pattern
    ///
    def pathMatches(pattern: String, path: String): Bool = {
        let patternParts = String.split(regex="/", pattern);
        let pathParts = String.split(regex="/", path);
        
        if (List.length(patternParts) != List.length(pathParts))
            false
        else
            List.zip(patternParts, pathParts) |> List.forAll(match (pat, pth) ->
                if (String.startsWith(prefix="{", pat) and String.endsWith(suffix="}", pat))
                    true  // Parameter matches anything
                else
                    pat == pth
            )
    }
    
    ///
    /// Extract path parameters from URL
    ///
    def extractPathParams(pattern: String, path: String): Map[String, String] = {
        let patternParts = String.split(regex="/", pattern);
        let pathParts = String.split(regex="/", path);
        
        List.zip(patternParts, pathParts)
            |> List.filterMap(match (pat, val) -> 
                if (String.startsWith(prefix="{", pat) and String.endsWith(suffix="}", pat)) {
                    let key = String.slice(start=1, end=String.length(pat)-1, pat);
                    Some((key, val))
                } else {
                    None
                })
            |> List.toMap
    }
    
    ///
    /// Extract query parameters from exchange
    ///
    def extractQueryParams(exchange: HttpExchange): Map[String, String] \ IO = {
        let queryString = exchange.getRequestURI().getQuery();
        if (Object.isNull(queryString)) {
            Map.empty()
        } else {
            String.split(regex="&", queryString)
                |> List.filterMap(pair -> {
                    let parts = String.split(regex="=", pair);
                    match parts {
                        case k :: v :: _ => Some((k, v))
                        case _ => None
                    }
                })
                |> List.toMap
        }
    }
    
    ///
    /// Read request body as string
    ///
    def readRequestBody(exchange: HttpExchange): Option[String] \ IO = {
        let inputStream = exchange.getRequestBody();
        let reader = new BufferedReader(new InputStreamReader(inputStream));
        let line = reader.readLine();
        
        if (Object.isNull(line)) None else Some(line)
    }
    
    ///
    /// Write response
    ///
    def writeResponse(exchange: HttpExchange, response: Response): Unit \ IO = {
        let Response.Response(r) = response;
        let statusCode = Status.toCode(r#status);
        let body = r#body;
        
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        let bytes = body.getBytes();
        exchange.sendResponseHeaders(statusCode, Int32.toInt64(Array.length(bytes)));
        let outputStream = exchange.getResponseBody();
        outputStream.write(bytes);
        outputStream.close();
        exchange.close()
    }
    
    ///
    /// Write HTML response
    ///
    def writeHtmlResponse(exchange: HttpExchange, html: String): Unit \ IO = {
        exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
        let bytes = html.getBytes();
        exchange.sendResponseHeaders(200, Int32.toInt64(Array.length(bytes)));
        let outputStream = exchange.getResponseBody();
        outputStream.write(bytes);
        outputStream.close();
        exchange.close()
    }
}

///
/// OpenAPI specification generation
///
mod OpenApi {
    use Json.JsonElement
    use Json.JsonElement.{JsonObject, JsonString, JsonArray, JsonNumber, JsonBool}
    
    ///
    /// OpenAPI info section
    ///
    pub enum ApiInfo {
        case ApiInfo({
            title = String,
            version = String,
            description = Option[String]
        })
    }
    
    ///
    /// Generate OpenAPI 3.0 specification from routes
    ///
    pub def generate(info: ApiInfo, routes: List[Route[ef]]): String = {
        let ApiInfo.ApiInfo(i) = info;
        
        let infoObj = Map#{
            "title" => JsonString(i#title),
            "version" => JsonString(i#version)
        } |> (m -> match i#description {
            case Some(desc) => Map.insert("description", JsonString(desc), m)
            case None => m
        });
        
        let paths = generatePaths(routes);
        
        let spec = Map#{
            "openapi" => JsonString("3.0.3"),
            "info" => JsonObject(infoObj),
            "paths" => JsonObject(paths)
        };
        
        Json.Write.toPrettyString(2, JsonObject(spec))
    }
    
    ///
    /// Generate paths section from routes
    ///
    def generatePaths(routes: List[Route[ef]]): Map[String, JsonElement] = {
        // First group routes by path
        let groupedByPath = List.foldLeft((acc, route) -> {
            let Route.Route(method, path, _, metadata) = route;
            let pathKey = convertPathToOpenApi(path);
            let existing = Map.getWithDefault(pathKey, Nil, acc);
            Map.insert(pathKey, (method, metadata) :: existing, acc)
        }, Map.empty(), routes);
        
        // Then convert each path's routes to operations
        Map.map((methodMetadataList) -> {
            let operations = List.foldLeft((opMap, methodMetadata) -> {
                let (method, metadata) = methodMetadata;
                let operation = generateOperation(method, metadata);
                let methodKey = methodToString(method);
                Map.insert(methodKey, operation, opMap)
            }, Map.empty(), methodMetadataList);
            JsonObject(operations)
        }, groupedByPath)
    }
    
    ///
    /// Convert path pattern from "{id}" to OpenAPI format "{id}"
    /// (They're the same, but we might want to add validation later)
    ///
    def convertPathToOpenApi(path: String): String = path
    
    ///
    /// Convert Method to lowercase string for OpenAPI
    ///
    def methodToString(method: Method): String = match method {
        case Method.Get => "get"
        case Method.Post => "post"
        case Method.Put => "put"
        case Method.Delete => "delete"
        case Method.Patch => "patch"
    }
    
    ///
    /// Generate operation object for a route
    ///
    def generateOperation(method: Method, metadata: RouteMetadata): JsonElement = {
        let RouteMetadata.RouteMetadata(m) = metadata;
        
        let baseOp = Map#{
            "responses" => JsonObject(Map#{
                "200" => JsonObject(Map#{
                    "description" => JsonString(
                        match m#responseDescription {
                            case Some(desc) => desc
                            case None => "Successful response"
                        }
                    ),
                    "content" => JsonObject(Map#{
                        "application/json" => JsonObject(Map#{
                            "schema" => JsonObject(Map#{
                                "type" => JsonString("object")
                            })
                        })
                    })
                })
            })
        };
        
        let withSummary = match m#summary {
            case Some(s) => Map.insert("summary", JsonString(s), baseOp)
            case None => baseOp
        };
        
        let withDesc = match m#description {
            case Some(d) => Map.insert("description", JsonString(d), withSummary)
            case None => withSummary
        };
        
        let withTags = if (List.isEmpty(m#tags)) {
            withDesc
        } else {
            let tagArray = List.map(tag -> JsonString(tag), m#tags);
            Map.insert("tags", JsonArray(tagArray), withDesc)
        };
        
        let withRequestBody = match (method, m#requestBodyDescription) {
            case (Method.Post, Some(desc)) => Map.insert("requestBody", JsonObject(Map#{
                "description" => JsonString(desc),
                "required" => JsonBool(true),
                "content" => JsonObject(Map#{
                    "application/json" => JsonObject(Map#{
                        "schema" => JsonObject(Map#{
                            "type" => JsonString("object")
                        })
                    })
                })
            }), withTags)
            case (Method.Put, Some(desc)) => Map.insert("requestBody", JsonObject(Map#{
                "description" => JsonString(desc),
                "required" => JsonBool(true),
                "content" => JsonObject(Map#{
                    "application/json" => JsonObject(Map#{
                        "schema" => JsonObject(Map#{
                            "type" => JsonString("object")
                        })
                    })
                })
            }), withTags)
            case (Method.Patch, Some(desc)) => Map.insert("requestBody", JsonObject(Map#{
                "description" => JsonString(desc),
                "required" => JsonBool(true),
                "content" => JsonObject(Map#{
                    "application/json" => JsonObject(Map#{
                        "schema" => JsonObject(Map#{
                            "type" => JsonString("object")
                        })
                    })
                })
            }), withTags)
            case _ => withTags
        };
        
        JsonObject(withRequestBody)
    }
    
    ///
    /// Create a route that serves the OpenAPI specification
    ///
    pub def specRoute(info: ApiInfo, routes: List[Route[ef]]): Route[ef] = 
        Route.Route(Method.Get, "/openapi.json", _req -> checked_ecast({
            let spec = generate(info, routes);
            Response.ok(spec)
        }), RouteMetadata.empty())
    
    ///
    /// Create a route that serves Scalar API documentation
    ///
    pub def docsRoute(): Route[ef] = 
        Route.Route(Method.Get, "/api/docs", _req -> checked_ecast({
            let html = buildScalarHtml();
            Response.Response({
                status = Status.Ok,
                body = html
            })
        }), RouteMetadata.empty())
    
    ///
    /// Build HTML page with Scalar for API documentation
    ///
    def buildScalarHtml(): String =
        "<!DOCTYPE html>" +
        "<html>" +
        "<head>" +
        "<title>API Documentation</title>" +
        "<meta charset=\"utf-8\" />" +
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />" +
        "</head>" +
        "<body>" +
        "<script id=\"api-reference\" data-url=\"/openapi.json\"></script>" +
        "<script src=\"https://cdn.jsdelivr.net/npm/@scalar/api-reference\"></script>" +
        "</body>" +
        "</html>"
    
    ///
    /// Helper to create API documentation routes
    ///
    pub def createDocsRoutes(info: ApiInfo, routes: List[Route[ef]]): List[Route[ef]] = 
        List#{
            Route.Route(Method.Get, "/openapi.json", _req -> checked_ecast({
                let spec = generate(info, routes);
                Response.ok(spec)
            }), RouteMetadata.empty()),
            Route.Route(Method.Get, "/api/docs", _req -> checked_ecast({
                let html = buildScalarHtml();
                Response.Response({
                    status = Status.Ok,
                    body = html
                })
            }), RouteMetadata.empty())
        }
    
    ///
    /// Serve API with automatic documentation routes
    ///
    pub def serveWithDocs(port: Int32, info: ApiInfo, routes: List[Route[ef]]): Unit \ IO = {
        let docsRoutes = createDocsRoutes(info, routes);
        let allRoutes = List.append(routes, docsRoutes);
        Server.serve(port, allRoutes)
    }
}