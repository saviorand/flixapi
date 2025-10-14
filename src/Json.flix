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

