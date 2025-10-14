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

