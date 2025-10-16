import Vapor

public struct CORSMiddleware: Middleware, Sendable {
    public struct Configuration: Sendable {
        public var allowedOrigins: [String]
        public var allowedMethods: [HTTPMethod]
        public var allowedHeaders: [HTTPHeaders.Name]
        public var allowCredentials: Bool
        public var maxAge: Int?

        public init(
            allowedOrigins: [String] = ["*"],
            allowedMethods: [HTTPMethod] = [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS, .HEAD],
            allowedHeaders: [HTTPHeaders.Name] = [.authorization, .contentType],
            allowCredentials: Bool = false,
            maxAge: Int? = nil
        ) {
            self.allowedOrigins = allowedOrigins
            self.allowedMethods = allowedMethods
            self.allowedHeaders = allowedHeaders
            self.allowCredentials = allowCredentials
            self.maxAge = maxAge
        }
    }

    public let configuration: Configuration

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        if request.method == .OPTIONS {
            var res = Response(status: .noContent)
            addCORSHeaders(to: &res, request: request)
            return request.eventLoop.future(res)
        }
        return next.respond(to: request).map { res in
            var response = res
            self.addCORSHeaders(to: &response, request: request)
            return response
        }
    }

    // public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
    //     if request.method == .OPTIONS {
    //         var res = Response(status: .noContent)
    //             addCORSHeaders(to: &res, request: request)
    //             return request.eventLoop.future(res)
    //     }

    //     return next.respond(to: request).flatMapError { error in
    //         let res = ErrorMiddleware.default(environment: request.application.environment)
    //             .respond(to: request, chainingTo: next)
    //             return res
    //     }
    //     .map { res in
    //         var response = res
    //             self.addCORSHeaders(to: &response, request: request)
    //             return response
    //     }
    // }

    private func addCORSHeaders(to response: inout Response, request: Request) {
        let originHeader = request.headers.first(name: .origin) ?? "*"
        if configuration.allowedOrigins.contains("*") ||
            configuration.allowedOrigins.contains(originHeader) {
            response.headers.replaceOrAdd(name: .accessControlAllowOrigin, value: originHeader)
        }
        response.headers.replaceOrAdd(
            name: .accessControlAllowMethods,
            value: configuration.allowedMethods.map { $0.rawValue }.joined(separator: ",")
        )
        response.headers.replaceOrAdd(
            name: .accessControlAllowHeaders,
            value: configuration.allowedHeaders.map { $0.description }.joined(separator: ",")
        )
        if configuration.allowCredentials {
            response.headers.replaceOrAdd(name: .accessControlAllowCredentials, value: "true")
        }
        if let maxAge = configuration.maxAge {
            response.headers.replaceOrAdd(name: .accessControlMaxAge, value: "\(maxAge)")
        }
    }
}

public extension CORSMiddleware.Configuration {
    static let `default` = CORSMiddleware.Configuration()
}
