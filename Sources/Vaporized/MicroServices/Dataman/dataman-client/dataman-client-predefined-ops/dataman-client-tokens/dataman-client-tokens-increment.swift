import Foundation
import Structures
import Surfaces
import Interfaces
import Vapor
import plate

public extension DatamanClient {
    func incrementUsage(id: Int, on req: Request) async throws {
        let dr = DatamanRequest(
            operation: .update,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object(["id": .int(id)]),
            values:    .object(["usage_count": .int(1)]),
            fieldTypes: [
                "id":          .integer,
                "usage_count": .integer
            ]
        )
        _ = try await send(dr, on: req)
    }
}
