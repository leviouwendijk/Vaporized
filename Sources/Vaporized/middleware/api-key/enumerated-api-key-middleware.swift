import Foundation
import Interfaces
import Surfaces
import Vapor

public struct EnumeratedAPIKeyMiddleware: Middleware, Sendable {
    let style: APIKeyStyle
    let expectedKey: String

    public init(
        style: APIKeyStyle = .authorizationBearer,
        expectedKey: String
    ) {
        self.style = style
        self.expectedKey = expectedKey
    }

    public func respond(
        to request: Request,
        chainingTo next: Responder
    ) -> EventLoopFuture<Response> {
        let logger = request.application.standardLogger
        let presented: String?
        if style == .authorizationBearer {
            presented = request.headers.bearerAuthorization?.token
        } else if let header = style.headerName {
            presented = request.headers.first(name: header)
        } else {
            presented = nil
        }
        guard let key = presented, key == expectedKey else {
            logger.warn("APIKeyMiddleware: missing/invalid key via '\(style.rawValue)' style")
            let res = Response(status: .unauthorized)
            return request.eventLoop.future(res)
        }
        logger.debug("APIKeyMiddleware: validated via '\(style.rawValue)'")
        return next.respond(to: request)
    }
}
