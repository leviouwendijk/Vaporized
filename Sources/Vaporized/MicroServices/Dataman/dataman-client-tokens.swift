import Vapor
import Interfaces
import Surfaces

public extension DatamanClient {
    func fetchValidTokensTokenRow(ip: String, on req: Request) async throws -> TokensTokenRow? {
        let dmReq = CaptcherRequest(operation: .fetch, clientIp: ip).datamanRequest()
        let res = try await send(dmReq, on: req)
        guard let obj = try? res.results?.first?.objectValue else { return nil }

        let idStr      = try obj["id"]!.stringValue
        let hashed     = try obj["hashed_token"]!.stringValue
        let expStr     = try obj["expires_at"]!.stringValue
        let uses       = try obj["usage_count"]!.intValue
        let maxUses    = try obj["max_usages"]!.intValue
        guard let id = UUID(uuidString: idStr),
              let expiresAt = ISO8601DateFormatter().date(from: expStr) else {
            return nil
        }

        if expiresAt < Date() {
            try await invalidateToken(id: id, on: req)
            return nil
        }
        return TokensTokenRow(
            id: id, 
            hashed: hashed,
            expiresAt: expiresAt,
            usageCount: uses,
            maxUsages: maxUses
        )
    }

    func fetchValidTokensTokenRow(hashed: String, on req: Request) async throws -> TokensTokenRow? {
        let dmReq = DatamanRequest(
            operation: .fetch,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object([
                "hashed_token": .string(hashed),
                "invalidated":  .bool(false)
            ]),
            values: nil,
            order: .object(["created_at": .string("DESC")]),
            limit: 1
        )
        let res = try await send(dmReq, on: req)
        guard let obj = try? res.results?.first?.objectValue else { return nil }

        let idStr    = try obj["id"]!.stringValue
        let expStr   = try obj["expires_at"]!.stringValue
        let uses     = try obj["usage_count"]!.intValue
        let maxUses  = try obj["max_usages"]!.intValue
        guard let id = UUID(uuidString: idStr),
              let expiresAt = ISO8601DateFormatter().date(from: expStr) else {
            return nil
        }
        if expiresAt < Date() {
            try await invalidateToken(id: id, on: req)
            return nil
        }
        return TokensTokenRow(
            id: id,
            hashed: hashed,
            expiresAt: expiresAt,
            usageCount: uses,
            maxUsages: maxUses
        )
    }

    func createTokensTokenRow(ip: String, rawToken: String, on req: Request) async throws {
        let dr = CaptcherRequest(
            operation: .create,
            clientIp:  ip,
            rawToken:  rawToken
        ).datamanRequest()
        _ = try await send(dr, on: req)
    }

    func invalidateToken(id: UUID, on req: Request) async throws {
        let dr = DatamanRequest(
            operation: .update,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object(["id": .string(id.uuidString)]),
            values:    .object(["invalidated": .bool(true)])
        )
        _ = try await send(dr, on: req)
    }

    func incrementUsage(id: UUID, on req: Request) async throws {
        let dr = DatamanRequest(
            operation: .update,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object(["id": .string(id.uuidString)]),
            values:    .object(["usage_count": .int(1)])
        )
        _ = try await send(dr, on: req)
    }
}
