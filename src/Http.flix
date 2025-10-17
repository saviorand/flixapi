///
/// HTTP core types and utilities
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
/// CORS configuration
///
pub enum CorsConfig {
    /// Allow all origins (*)
    case AllowAll
    /// Allow specific origins only
    case AllowOrigins(List[String])
    /// Disable CORS headers
    case Disabled
}

mod CorsConfig {
    ///
    /// Get the Access-Control-Allow-Origin header value
    ///
    pub def getAllowOriginHeader(config: CorsConfig, requestOrigin: Option[String]): Option[String] = 
        match config {
            case CorsConfig.AllowAll => Some("*")
            case CorsConfig.AllowOrigins(origins) =>
                match requestOrigin {
                    case Some(origin) if List.memberOf(origin, origins) => Some(origin)
                    case _ => None
                }
            case CorsConfig.Disabled => None
        }
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

