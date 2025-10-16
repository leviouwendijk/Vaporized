import Foundation
import Structures
import Surfaces
import Interfaces
import Vapor
import plate

public struct DatamanClient: Sendable {
    public let baseURL: URI
    private let client: Client
    private let authorization: APIAuthorzationMethod

    public init(baseURL: URI, client: Client, authorization: APIAuthorzationMethod) {
        self.baseURL = baseURL
        self.client = client
        self.authorization = authorization
    }

    public func send(
        _ datamanRequest: DatamanRequest,
        on req: Request
    ) async throws -> DatamanResponse {
        let response = try await client.post(baseURL) { post in
            let headers = authorization.headers() 
            post.headers.add(contentsOf: headers)
            try post.content.encode(datamanRequest, as: .json)
        }
        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "Dataman returned \(response.status)")
        }
        return try response.content.decode(DatamanResponse.self)
    }
}
