import Foundation
import Interfaces
import Surfaces
import Vapor

public struct SimpleAPIKeyMiddleware: Middleware {
    public let header: String
    public let expectedKey: String

    public init(
        header: String = "x-api-key", // backwards compatible
        expectedKey: String
    ) {
        self.header = header
        self.expectedKey = expectedKey
    }

    public func respond(to req: Request, chainingTo next: any Responder) -> EventLoopFuture<Response> {
        guard
            let provided = req.headers.first(name: .init(header)),
            provided == expectedKey
        else {
            return req.eventLoop.makeSucceededFuture(
                Response(
                    status: .unauthorized, 
                    body: .init(string: "Unauthorized: Invalid or missing API key")
                )
            )
        }
        return next.respond(to: req)
    }
}
