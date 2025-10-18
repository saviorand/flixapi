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
    /// Named schema definition for components section
    ///
    pub enum NamedSchema {
        case NamedSchema({
            name = String,
            schema = Schema
        })
    }
    
    ///
    /// OpenAPI Schema representation
    ///
    pub enum Schema {
        case ObjectSchema(Map[String, Schema])
        case ArraySchema(Schema)
        case StringSchema
        case NumberSchema
        case IntegerSchema
        case BooleanSchema
        case RefSchema(String)
        case AnySchema
    }
    
    mod Schema {
        use Json.JsonElement
        use Json.JsonElement.{JsonObject, JsonString}
        
        ///
        /// Convert Schema to JSON for OpenAPI spec
        ///
        pub def toJson(schema: Schema): JsonElement = match schema {
            case ObjectSchema(properties) => {
                let propsJson = Map.map(s -> toJson(s), properties);
                JsonObject(Map#{
                    "type" => JsonString("object"),
                    "properties" => JsonObject(propsJson)
                })
            }
            case ArraySchema(itemSchema) => {
                JsonObject(Map#{
                    "type" => JsonString("array"),
                    "items" => toJson(itemSchema)
                })
            }
            case StringSchema => JsonObject(Map#{"type" => JsonString("string")})
            case NumberSchema => JsonObject(Map#{"type" => JsonString("number")})
            case IntegerSchema => JsonObject(Map#{"type" => JsonString("integer")})
            case BooleanSchema => JsonObject(Map#{"type" => JsonString("boolean")})
            case RefSchema(ref) => JsonObject(Map#{"$ref" => JsonString("#/components/schemas/${ref}")})
            case AnySchema => JsonObject(Map#{"type" => JsonString("object")})
        }
    }
    
    ///
    /// Generate OpenAPI 3.0 specification from routes
    ///
    pub def generate(info: ApiInfo, routes: List[Route[ef]]): String = 
        generateWithSchemas(info, routes, Nil)
    
    ///
    /// Generate OpenAPI 3.0 specification with named component schemas
    ///
    pub def generateWithSchemas(info: ApiInfo, routes: List[Route[ef]], schemas: List[NamedSchema]): String = {
        let ApiInfo.ApiInfo(i) = info;
        
        let infoObj = Map#{
            "title" => JsonString(i#title),
            "version" => JsonString(i#version)
        } |> (m -> Option.map(desc -> Map.insert("description", JsonString(desc), m), i#description) |> Option.getWithDefault(m));
        
        let paths = generatePaths(routes);
        
        // Helper to indent JSON by adding 2 spaces to each line
        def indent(s: String): String = 
            String.replace(src = "\n", dst = "\n  ", s);
        
        // Build component schemas if provided
        let componentsOpt = if (List.isEmpty(schemas)) {
            None
        } else {
            let schemaMap = schemas 
                |> List.map(match NamedSchema.NamedSchema(ns) -> (ns#name, Schema.toJson(ns#schema)))
                |> List.toMap;
            Some(Json.Write.toPrettyString(2, JsonObject(Map#{"schemas" => JsonObject(schemaMap)})))
        };
        
        // Manually construct JSON in correct order (Map sorts keys alphabetically)
        buildOpenApiJson(
            Json.Write.toPrettyString(2, JsonObject(infoObj)),
            Json.Write.toPrettyString(2, JsonObject(paths)),
            componentsOpt,
            indent
        )
    }
    
    ///
    /// Build OpenAPI JSON string with correct key ordering
    ///
    def buildOpenApiJson(infoJson: String, pathsJson: String, componentsOpt: Option[String], indent: String -> String): String = {
        let base = "{\n" +
                   "  \"openapi\": \"3.0.3\",\n" +
                   "  \"info\": ${indent(infoJson)},\n" +
                   "  \"paths\": ${indent(pathsJson)}";
        
        match componentsOpt {
            case Some(componentsJson) => "${base},\n  \"components\": ${indent(componentsJson)}\n}"
            case None => "${base}\n}"
        }
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
            Map.insert(pathKey, (method, path, metadata) :: existing, acc)
        }, Map.empty(), routes);
        
        // Then convert each path's routes to operations
        Map.map((methodPathMetadataList) -> {
            let operations = List.foldLeft((opMap, methodPathMetadata) -> {
                let (method, path, metadata) = methodPathMetadata;
                let operation = generateOperation(method, path, metadata);
                let methodKey = methodToString(method);
                Map.insert(methodKey, operation, opMap)
            }, Map.empty(), methodPathMetadataList);
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
    /// Check if a method should have a request body
    ///
    def shouldHaveRequestBody(method: Method): Bool = match method {
        case Method.Post => true
        case Method.Put => true
        case Method.Patch => true
        case _ => false
    }
    
    ///
    /// Extract path parameters from a path string
    /// e.g., "/todos/{id}/items/{itemId}" => ["id", "itemId"]
    ///
    def extractPathParams(path: String): List[String] = 
        path
        |> String.split(regex="/")
        |> List.filterMap(part -> 
            if (String.startsWith(prefix="{", part) and String.endsWith(suffix="}", part))
                Some(String.slice(start=1, end=String.length(part)-1, part))
            else
                None
        )
    
    ///
    /// Generate operation object for a route
    ///
    def generateOperation(method: Method, path: String, metadata: RouteMetadata): JsonElement = {
        let RouteMetadata.RouteMetadata(m) = metadata;
        
        let responseSchema = m#responseSchema 
            |> Option.map(Schema.toJson) 
            |> Option.getWithDefault(JsonObject(Map#{"type" => JsonString("object")}));
        
        let baseOp = Map#{
            "responses" => JsonObject(Map#{
                "200" => JsonObject(Map#{
                    "description" => JsonString(Option.getWithDefault("Successful response", m#responseDescription)),
                    "content" => JsonObject(Map#{
                        "application/json" => JsonObject(Map#{"schema" => responseSchema})
                    })
                })
            })
        };
        
        baseOp
        |> insertOptional("summary", m#summary |> Option.map(JsonString))
        |> insertOptional("description", m#description |> Option.map(JsonString))
        |> insertOptional("tags", if (List.isEmpty(m#tags)) None else Some(JsonArray(List.map(JsonString, m#tags))))
        |> addRequestBodyIfNeeded(method, m#requestBodyDescription, m#requestSchema)
        |> addPathParametersIfNeeded(path)
        |> JsonObject
    }
    
    ///
    /// Insert a key-value pair into a map if the value is Some
    ///
    def insertOptional(key: String, valueOpt: Option[JsonElement], m: Map[String, JsonElement]): Map[String, JsonElement] = 
        match valueOpt {
            case Some(value) => Map.insert(key, value, m)
            case None => m
        }
    
    ///
    /// Add request body to operation if method supports it and metadata provides it
    ///
    def addRequestBodyIfNeeded(method: Method, descOpt: Option[String], schemaOpt: Option[Schema], m: Map[String, JsonElement]): Map[String, JsonElement] = {
        if (not shouldHaveRequestBody(method)) {
            m
        } else {
            match (descOpt, schemaOpt) {
                case (None, None) => m
                case _ => {
                    let desc = Option.getWithDefault("Request body", descOpt);
                    let schema = schemaOpt |> Option.map(Schema.toJson) |> Option.getWithDefault(JsonObject(Map#{"type" => JsonString("object")}));
                    Map.insert("requestBody", JsonObject(Map#{
                        "description" => JsonString(desc),
                        "required" => JsonBool(true),
                        "content" => JsonObject(Map#{
                            "application/json" => JsonObject(Map#{"schema" => schema})
                        })
                    }), m)
                }
            }
        }
    }
    
    ///
    /// Add path parameters to operation if the path contains any
    ///
    def addPathParametersIfNeeded(path: String, m: Map[String, JsonElement]): Map[String, JsonElement] = {
        let pathParams = extractPathParams(path);
        if (List.isEmpty(pathParams)) {
            m
        } else {
            let paramArray = pathParams |> List.map(paramName -> JsonObject(Map#{
                "name" => JsonString(paramName),
                "in" => JsonString("path"),
                "required" => JsonBool(true),
                "schema" => JsonObject(Map#{"type" => JsonString("string")})
            }));
            Map.insert("parameters", JsonArray(paramArray), m)
        }
    }
    
    ///
    /// Create a route that serves the OpenAPI specification
    ///
    pub def specRoute(info: ApiInfo, routes: List[Route[ef]]): Route[ef] = 
        specRouteWithSchemas(info, routes, Nil)
    
    ///
    /// Create a route that serves the OpenAPI specification with named schemas
    ///
    pub def specRouteWithSchemas(info: ApiInfo, routes: List[Route[ef]], schemas: List[NamedSchema]): Route[ef] = 
        Route.Route(Method.Get, "/openapi.json", _req -> checked_ecast({
            let spec = generateWithSchemas(info, routes, schemas);
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
        createDocsRoutesWithSchemas(info, routes, Nil)
    
    ///
    /// Helper to create API documentation routes with named schemas
    ///
    pub def createDocsRoutesWithSchemas(info: ApiInfo, routes: List[Route[ef]], schemas: List[NamedSchema]): List[Route[ef]] = 
        specRouteWithSchemas(info, routes, schemas) :: docsRoute() :: Nil
    
    ///
    /// Serve API with automatic documentation routes
    ///
    pub def serveWithDocs(port: Int32, corsConfig: CorsConfig, info: ApiInfo, routes: List[Route[ef]]): Unit \ IO = 
        serveWithDocsAndSchemas(port, corsConfig, info, routes, Nil)
    
    ///
    /// Serve API with automatic documentation routes and named component schemas
    ///
    pub def serveWithDocsAndSchemas(port: Int32, corsConfig: CorsConfig, info: ApiInfo, routes: List[Route[ef]], schemas: List[NamedSchema]): Unit \ IO = {
        let docsRoutes = createDocsRoutesWithSchemas(info, routes, schemas);
        let allRoutes = List.append(routes, docsRoutes);
        Server.serve(port, corsConfig, allRoutes)
    }
}

