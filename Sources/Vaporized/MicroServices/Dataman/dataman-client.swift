import Surfaces
import Vapor

public struct DatamanClient: Sendable {
    public let baseURL: URI
    private let client: Client

    public init(baseURL: URI, client: Client) {
        self.baseURL = baseURL
        self.client = client
    }

    public func send(
        _ datamanRequest: DatamanRequest,
        on req: Request
    ) async throws -> DatamanResponse {
        let response = try await client.post(baseURL) { post in
            try post.content.encode(datamanRequest, as: .json)
        }
        guard (200..<300).contains(response.status.code) else {
            throw Abort(.badGateway, reason: "Dataman returned \(response.status)")
        }
        return try response.content.decode(DatamanResponse.self)
    }
}
