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

public extension DatamanClient {
    func fetchValidTokensTokenRow(ip: String, on req: Request) async throws -> TokensTokenRow? {
        req.logger.info("→ fetchValidTokensTokenRow(ip:\(ip))")
        
        let dmReq = try CaptcherRequest(
            operation: .fetch,
            clientIp: ip,
            fieldTypes: try PSQLFieldTypeRegistry.table(named: "captcha_tokens")
        ).datamanRequest()
        req.logger.debug("  -> DatamanRequest: \(dmReq)")
        
        let res = try await send(dmReq, on: req)
        req.logger.debug("  <- raw DatamanResponse: \(res)")
        guard let array = res.results else {
            req.logger.warning("  <- no results array")
            return nil
        }
        req.logger.debug("  <- results.count = \(array.count)")

        guard let first = array.first else {
            req.logger.warning("  <- results array empty")
            return nil
        }
        req.logger.debug("  <- first JSONValue = \(first)")

        let obj: [String: JSONValue]
        do {
            obj = try first.objectValue
        } catch {
            req.logger.error("  ← objectValue() threw \(error)")
            return nil
        }
        req.logger.debug("  <- objectValue keys = \(obj.keys)")

        let idInt: Int
        do {
            idInt = try obj["id"]!.intValue
        } catch {
            req.logger.error("  ← id.intValue threw \(error)")
            return nil
        }
        req.logger.debug("  <- parsed id = \(idInt)")

        let hashed   = try obj["hashed_token"]!.stringValue
        let expStr   = try obj["expires_at"]!.stringValue
        let uses     = try obj["usage_count"]!.intValue
        let maxUses  = try obj["max_usages"]!.intValue
        req.logger.debug("  <- parsed other fields")

        guard let expiresAt = StandardDateFormatter.postgres.date(from: expStr) else {
            req.logger.warning("failed to parse expires_at \(expStr)")
            return nil
        }
        req.logger.debug("  <- parsed expiresAt = \(expiresAt)")

        if expiresAt < Date() {
            req.logger.info("  ← token expired, invalidating and returning nil")
            try await invalidateToken(id: idInt, on: req)
            return nil
        }

        req.logger.info("  ← fetch succeeded, reusing row \(idInt)")
        return TokensTokenRow(
            id:         idInt,
            hashed:     hashed,
            expiresAt:  expiresAt,
            usageCount: uses,
            maxUsages:  maxUses
        )
    }

    // func fetchValidTokensTokenRow(ip: String, on req: Request) async throws -> TokensTokenRow? {
    //     req.logger.debug("Captcher fetching token for IP \(ip)")

    //     let table = "captcha_tokens"
    //     let fieldTypes = try PSQLFieldTypeRegistry.table(named: table)

    //     let dmReq = try CaptcherRequest(
    //         operation: .fetch,
    //         clientIp: ip,
    //         fieldTypes: fieldTypes
    //     ).datamanRequest()

    //     req.logger.debug("→ FETCH DatamanRequest: \(dmReq)")

    //     let res = try await send(dmReq, on: req)
    //     guard let obj = try? res.results?.first?.objectValue else { return nil }

    //     req.logger.debug("← FETCH response raw JSON: \(res)")

    //     let id       = try obj["id"]!.intValue
    //     let hashed   = try obj["hashed_token"]!.stringValue
    //     let expStr   = try obj["expires_at"]!.stringValue
    //     let uses     = try obj["usage_count"]!.intValue
    //     let maxUses  = try obj["max_usages"]!.intValue

        // guard let expiresAt = StandardDateFormatter.postgres.date(from: expStr) else {
        //     req.logger.warning("failed to parse expires_at \(expStr)")
        //     return nil
        // }

    //     if expiresAt < Date() {
    //         try await invalidateToken(id: id, on: req)
    //         return nil
    //     }

    //     return TokensTokenRow(
    //         id: id,
    //         hashed: hashed,
    //         expiresAt: expiresAt,
    //         usageCount: uses,
    //         maxUsages: maxUses
    //     )
    // }

    func fetchValidTokensTokenRow(hashed: String, on req: Request) async throws -> TokensTokenRow? {
        let table = "captcha_tokens"
        let fieldTypes = try PSQLFieldTypeRegistry.table(named: table)

        let dmReq = DatamanRequest(
            operation: .fetch,
            database:  "tokens",
            table:     "captcha_tokens",
            criteria:  .object([
                "hashed_token": .string(hashed),
                "invalidated":  .bool(false)
            ]),
            values:    nil,
            fieldTypes: fieldTypes,
            order:     .object(["created_at": .string("DESC")]),
            limit:     1
        )

        let res = try await send(dmReq, on: req)
        guard let obj = try? res.results?.first?.objectValue else { return nil }

        let id       = try obj["id"]!.intValue
        let expStr   = try obj["expires_at"]!.stringValue
        let uses     = try obj["usage_count"]!.intValue
        let maxUses  = try obj["max_usages"]!.intValue

        guard let expiresAt = StandardDateFormatter.postgres.date(from: expStr) else {
            req.logger.warning("failed to parse expires_at \(expStr)")
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
