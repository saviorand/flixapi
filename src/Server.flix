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

