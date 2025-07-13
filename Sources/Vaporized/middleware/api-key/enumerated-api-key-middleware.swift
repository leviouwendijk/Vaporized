import Foundation
import Interfaces
import Surfaces
import Vapor

public enum APIKeyHeaderStyle: String, CaseIterable, Sendable {
    case XAPIKEY             = "X-API-KEY"
    case xapikey             = "x-api-key"
    case XApiKey             = "X-Api-Key"
    case authorizationBearer = "Authorization"  // for “Bearer <token>”

    public var headerName: HTTPHeaders.Name? {
        switch self {
        case .authorizationBearer:
            return .authorization
        default:
            return HTTPHeaders.Name(self.rawValue)
        }
    }
}

public struct EnumeratedAPIKeyMiddleware: Middleware, Sendable {
    let style: APIKeyHeaderStyle
    let expectedKey: String

    public init(
        style: APIKeyHeaderStyle = .XApiKey,
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
