///
/// Route definitions and metadata for REST API
///

///
/// Route metadata for OpenAPI documentation
///
pub enum RouteMetadata {
    case RouteMetadata({
        summary = Option[String],
        description = Option[String],
        tags = List[String],
        requestBodyDescription = Option[String],
        responseDescription = Option[String],
        requestSchema = Option[OpenApi.Schema],
        responseSchema = Option[OpenApi.Schema],
        responseStatus = Option[Int32]
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
            responseDescription = None,
            requestSchema = None,
            responseSchema = None,
            responseStatus = None
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
    
    ///
    /// Add request schema
    ///
    pub def withRequestSchema(schema: OpenApi.Schema, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({requestSchema = Some(schema) | m})
    
    ///
    /// Add response schema
    ///
    pub def withResponseSchema(schema: OpenApi.Schema, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({responseSchema = Some(schema) | m})
    
    ///
    /// Add response status code (default is 200)
    ///
    pub def withResponseStatus(status: Int32, metadata: RouteMetadata): RouteMetadata =
        let RouteMetadata.RouteMetadata(m) = metadata;
        RouteMetadata.RouteMetadata({responseStatus = Some(status) | m})
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

