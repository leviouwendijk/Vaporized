import Foundation
import Structures
import Surfaces
import Interfaces
import Vapor
import plate

public extension DatamanClient {
    func invalidateToken(id: Int, on req: Request) async throws {
        let dr = DatamanRequest(
            operation: .update,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object(["id": .int(id)]),
            values:    .object(["invalidated": .bool(true)]),
            fieldTypes: [
                "id":          .integer,
                "invalidated": .boolean
            ]
        )
        _ = try await send(dr, on: req)
    }
}
