import Foundation
import Structures
import Surfaces
import Interfaces
import Vapor
import plate

public extension DatamanClient {
    func createTokensTokenRow(ip: String, rawToken: String, on req: Request) async throws {
        let expiryDate = Date().addingTimeInterval(15 * 60)
        let expiry     = expiryDate.postgresTimestamp

        let dr = DatamanRequest(
            operation: .create,
            database: "tokens",
            table:    "captcha_tokens",
            criteria: nil,
            values: .object([
                "hashed_token": .string(hash(rawToken)),
                "expires_at":   .string(expiry),
                "max_usages":   .int(10),
                "ip_address":   .string(ip)
            ]),
            fieldTypes: [
                "hashed_token": .text,
                "expires_at":   .timestamptz,
                "max_usages":   .integer,
                "ip_address":   .text
            ]
        )

        _ = try await send(dr, on: req)
    }
}
