///
/// RestApi - A declarative REST API framework for Flix
///
mod RestApi {
    
    ///
    /// HTTP methods
    ///
    pub enum Method with Eq, ToString {
        case Get, Post, Put, Delete, Patch
    }
    
    ///
    /// API Error types
    ///
    pub enum ApiError with ToString {
        case BadRequest(String)
        case NotFound(String)
        case Unauthorized(String)
        case InternalError(String)
    }
    
    ///
    /// HTTP Response with status code and body
    ///
    pub enum Response[a] {
        case Response(Int32, a)
    }
    
    ///
    /// Handler function type - now effect polymorphic
    ///
    pub type alias RouteHandler[ef: Eff] = (Map[String, String], Map[String, String], Option[String]) -> Result[ApiError, (Int32, String)] \ ef

    ///
    /// Route definition with effect parameter
    ///
    pub enum Route[ef: Eff] {
        case Route(Method, String, RouteHandler[ef])
    }

    ///
    /// API metadata with effect parameter
    ///
    pub enum Api[ef: Eff] {
        case Api({
            title = String,
            version = String, 
            description = String,
            routes = List[Route[ef]]
        })
    }

    ///
    /// Create a GET route - effect polymorphic
    ///
    pub def get(path: String, rhandler: RouteHandler[ef]): Route[ef] =
        Route.Route(Method.Get, path, rhandler)

    ///
    /// Create a POST route - effect polymorphic
    ///
    pub def post(path: String, rhandler: RouteHandler[ef]): Route[ef] =
        Route.Route(Method.Post, path, rhandler)

    ///
    /// Create a DELETE route - effect polymorphic
    ///
    pub def delete(path: String, rhandler: RouteHandler[ef]): Route[ef] =
        Route.Route(Method.Delete, path, rhandler)    
    
    ///
    /// Helper to create a 200 OK response
    ///
    pub def ok(body: a): Response[a] = 
        Response.Response(200, body)
    
    ///
    /// Helper to create a 201 Created response
    ///
    pub def created(body: a): Response[a] =
        Response.Response(201, body)
    
    ///
    /// Helper to create a 204 No Content response
    ///
    pub def noContent(): Response[String] =
        Response.Response(204, "")
    
    ///
    /// Convert ApiError to HTTP status code and message
    ///
    pub def errorToResponse(err: ApiError): (Int32, String) = match err {
        case ApiError.BadRequest(msg)    => (400, msg)
        case ApiError.NotFound(msg)      => (404, msg)
        case ApiError.Unauthorized(msg)  => (401, msg)
        case ApiError.InternalError(msg) => (500, msg)
    }
}

///
/// JSON helpers for REST API
///
mod RestApi.Json {
    use Json.JsonElement
    use Json.ToJson
    use Json.FromJson
    use Json.JsonError
    
    ///
    /// Serialize a Flix value to JSON string
    ///
    pub def toJsonString(x: a): String with ToJson[a] =
        ToJson.toJson(x) |> Json.Write.toCompactString
    
    ///
    /// Parse JSON string to Flix value
    ///
    pub def fromJsonString(s: String): Result[String, a] with FromJson[a] =
        match Json.Parse.parse(s) {
            case None => Err("JSON parse error: invalid JSON")
            case Some(elem) => 
                FromJson.fromJson(elem) |> Result.mapErr(_ -> "JSON decode error")
        }
    
    ///
    /// Create a JSON response handler - effect polymorphic
    ///
    pub def jsonHandler(f: Map[String, String] -> Result[RestApi.ApiError, a] \ ef): RestApi.RouteHandler[ef] with ToJson[a] =
        (params, _, _) -> {
            match f(params) {
                case Ok(value) => 
                    let json = toJsonString(value);
                    Ok((200, json))
                case Err(err) => 
                    Err(err)
            }
        }

    ///
    /// Create a JSON body handler (POST/PUT) - effect polymorphic
    ///
    pub def jsonBodyHandler(f: a -> Result[RestApi.ApiError, b] \ ef): RestApi.RouteHandler[ef] with FromJson[a], ToJson[b] =
        (_, _, bodyOpt) -> {
            match bodyOpt {
                case None => Err(RestApi.ApiError.BadRequest("Request body required"))
                case Some(body) => 
                    match fromJsonString(body) {
                        case Err(msg) => Err(RestApi.ApiError.BadRequest(msg))
                        case Ok(input) => 
                            match f(input) {
                                case Ok(output) => Ok((200, toJsonString(output)))
                                case Err(err) => Err(err)
                            }
                    }
            }
        }
}

///
/// HTTP Server integration
///
mod RestApi.Server {
    import java.net.InetSocketAddress
    import java.lang.{Thread => JThread, InterruptedException}
    import com.sun.net.httpserver.{HttpServer => JavaHttpServer, HttpHandler, HttpExchange}
    import java.io.{BufferedReader, InputStreamReader, OutputStream}
    
    ///
    /// Start the REST API server
    ///
    pub def serve(port: Int32, api: RestApi.Api[ef]): Unit \ {IO} = {
        let RestApi.Api.Api(config) = api;
        let addr = new InetSocketAddress(port);
        let server = JavaHttpServer.create(addr, 0);
        
        // Group routes by base path to avoid conflicts
        let routesByPath = groupRoutesByBasePath(config#routes);
        Map.forEach((basePath, routes) -> 
            registerRoutesAtPath(server, basePath, routes), routesByPath);
        
        // Start server
        server.start();
        println("🚀 API Server running on http://localhost:${port}");
        
        // Keep alive
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
    def groupRoutesByBasePath(routes: List[RestApi.Route[ef]]): Map[String, List[RestApi.Route[ef]]] = {
        List.foldLeft((acc, route) -> {
            let RestApi.Route.Route(_, path, _) = route;
            let basePath = pathToJavaPattern(path);
            let existing = Map.getWithDefault(basePath, Nil, acc);
            Map.insert(basePath, route :: existing, acc)
        }, Map.empty(), routes)
    }

    ///
    /// Register all routes at a given base path with a multiplexing handler
    ///
    def registerRoutesAtPath(server: JavaHttpServer, basePath: String, routes: List[RestApi.Route[ef]]): Unit \ {IO} = {
        discard server.createContext(basePath, createMultiplexHandler(routes));
        ()
    }

    ///
    /// Create a handler that multiplexes between multiple routes
    ///
    def createMultiplexHandler(routes: List[RestApi.Route[ef]]): HttpHandler \ {IO} =
        new HttpHandler {
            def $handle(_this: HttpHandler, exchange: HttpExchange): Unit \ {IO, ef} = {
                let method = exchange.getRequestMethod();
                let path = exchange.getRequestURI().getPath();
                
                // Find matching route
                let matchingRoute = List.find(route -> {
                    let RestApi.Route.Route(routeMethod, routePath, _) = route;
                    methodMatches(method, routeMethod) and pathMatches(routePath, path)
                }, routes);
                
                match matchingRoute {
                    case Some(RestApi.Route.Route(_, pathPattern, rhandler)) =>
                        let params = extractPathParams(pathPattern, path);
                        let qparams = extractQueryParams(exchange);
                        let body = readRequestBody(exchange);
                        
                        match rhandler(params, qparams, body) {
                            case Ok((status, responseBody)) =>
                                writeJsonResponse(exchange, status, responseBody)
                            case Err(err) =>
                                let (status, msg) = RestApi.errorToResponse(err);
                                writeJsonResponse(exchange, status, msg)
                        }
                    case None =>
                        writeResponse(exchange, 404, "Not Found")
                }
            }
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
            List.zip(patternParts, pathParts) |> List.forAll(match (pat, val) ->
                if (String.startsWith(prefix="{", pat))
                    true  // Parameter matches anything
                else
                    pat == val
            )
    }
    
    ///
    /// Convert Flix path pattern to Java path
    ///
    def pathToJavaPattern(path: String): String = 
        // For now, just use the path as-is
        // TODO: Handle path parameters properly
        path
    
    ///
    /// Create a Java HttpHandler from a Flix handler
    ///
    // def createHttpHandler(expectedMethod: RestApi.Method, pathPattern: String, rhandler: RestApi.RouteHandler[ef]): HttpHandler \ {IO} =
    // new HttpHandler {
    //     def $handle(_this: HttpHandler, exchange: HttpExchange): Unit \ {IO, ef} = {
    //         let method = exchange.getRequestMethod();
    //         let path = exchange.getRequestURI().getPath();
            
    //         if (not methodMatches(method, expectedMethod)) {
    //             writeResponse(exchange, 405, "Method Not Allowed");
    //             ()
    //         } else {
    //             let params = extractPathParams(pathPattern, path);
    //             let qparams = extractQueryParams(exchange);
    //             let body = readRequestBody(exchange);
                
    //             match rhandler(params, qparams, body) {
    //                 case Ok((status, responseBody)) =>
    //                     writeJsonResponse(exchange, status, responseBody)
    //                 case Err(err) =>
    //                     let (status, msg) = RestApi.errorToResponse(err);
    //                     writeJsonResponse(exchange, status, msg)
    //             }
    //         }
    //     }
    // }

    ///
    /// Check if HTTP method matches
    ///
    def methodMatches(httpMethod: String, apiMethod: RestApi.Method): Bool =
        match apiMethod {
            case RestApi.Method.Get    => httpMethod == "GET"
            case RestApi.Method.Post   => httpMethod == "POST"  
            case RestApi.Method.Put    => httpMethod == "PUT"
            case RestApi.Method.Delete => httpMethod == "DELETE"
            case RestApi.Method.Patch  => httpMethod == "PATCH"
        }
    
    ///
    /// Extract path parameters from URL
    /// e.g. pattern="/todos/{id}" path="/todos/123" => Map#{"id" => "123"}
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
    /// Write JSON response
    ///
    def writeJsonResponse(exchange: HttpExchange, status: Int32, body: String): Unit \ IO = {
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        writeResponse(exchange, status, body)
    }
    
    ///
    /// Write generic response
    ///
    def writeResponse(exchange: HttpExchange, status: Int32, body: String): Unit \ IO = {
        let bytes = body.getBytes();
        exchange.sendResponseHeaders(status, Int32.toInt64(Array.length(bytes)));
        let outputStream = exchange.getResponseBody();
        outputStream.write(bytes);
        outputStream.close();
        exchange.close()
    }
}

///
/// OpenAPI specification generation
///
mod RestApi.OpenApi {
    
    ///
    /// Generate OpenAPI 3.0 JSON spec
    ///
    pub def generate(api: RestApi.Api[ef]): String = {
        let RestApi.Api.Api(config) = api;
        
        let paths = List.map(routeToPathItem, config#routes)
            |> List.map(match (path, item) -> "\"${path}\": ${item}")
            |> String.intercalate(", ");
        
        String.unlines(List#{
            "{",
            "  \"openapi\": \"3.0.0\",",
            "  \"info\": {",
            "    \"title\": \"${config#title}\",",
            "    \"version\": \"${config#version}\",",
            "    \"description\": \"${config#description}\"",
            "  },",
            "  \"paths\": {",
            "    ${paths}",
            "  }",
            "}"
        })
    }
    
    ///
    /// Convert route to OpenAPI path item
    ///
    def routeToPathItem(route: RestApi.Route[ef]): (String, String) = {
        let RestApi.Route.Route(method, path, _) = route;
        let methodName = String.toLowerCase(ToString.toString(method));
        
        let operation = String.unlines(List#{
            "    \"${methodName}\": {",
            "      \"responses\": {",
            "        \"200\": {",
            "          \"description\": \"Successful response\"",
            "        }",
            "      }",
            "    }"
        });
        
        (path, "{\n${operation}\n  }")
    }
}