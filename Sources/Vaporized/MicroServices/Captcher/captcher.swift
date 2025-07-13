import Vapor
import CryptoKit
import JWTKit
import Interfaces
import Surfaces

public struct Captcher: @unchecked Sendable {
    private let dataman: DatamanClient
    private let signer:  JWTSigner
    private let verifier: JWTSigner
    private let ttl: TimeInterval
    private let maxUses: Int

    public init(
        datamanClient: DatamanClient,
        publicKeyPEM: String,
        privateKeyPEM: String,
        tokenTTL: TimeInterval = 15 * 60,
        maxUsages: Int = 10
    ) throws {
        self.dataman  = datamanClient
        self.signer   = try JWTSigner.rs256(key: .private(pem: privateKeyPEM))
        self.verifier = try JWTSigner.rs256(key: .public(pem: publicKeyPEM))
        self.ttl      = tokenTTL
        self.maxUses  = maxUsages
    }

    public func issueToken(clientIp: String, on req: Request) async throws -> CaptcherResponse {
        if let row = try await dataman.fetchValidTokensTokenRow(ip: clientIp, on: req) {
            let payload = CaptcherJWTPayload(
                hashedToken: row.hashed,
                ipAddress:   clientIp,
                maxUsages:   row.maxUsages,
                exp:         .init(value: Date().addingTimeInterval(ttl))
            )
            let jwt = try signer.sign(payload)
            return CaptcherResponse(success: true, token: jwt, type: .reuse)
        }
        let raw    = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        try await dataman.createTokensTokenRow(ip: clientIp, rawToken: raw, on: req)
        let payload = CaptcherJWTPayload(
            hashedToken: hashed,
            ipAddress:   clientIp,
            maxUsages:   maxUses,
            exp:         .init(value: Date().addingTimeInterval(ttl))
        )
        let jwt = try signer.sign(payload)
        return CaptcherResponse(success: true, token: jwt, type: .new)
    }

    public func validateToken(_ jwtToken: String, clientIp: String, on req: Request) async -> CaptcherValidationResult {
        let payload: CaptcherJWTPayload
        do {
            payload = try verifier.verify(jwtToken, as: CaptcherJWTPayload.self)
        } catch JWTError.claimVerificationFailure {
            return .init(success: false, reason: .jwtExpired)
        } catch {
            return .init(success: false, reason: .signatureInvalid)
        }
        guard payload.ipAddress == clientIp else {
            return .init(success: false, reason: .ipMismatch)
        }
        guard let row = try? await dataman.fetchValidTokensTokenRow(hashed: payload.hashedToken, on: req) else {
            return .init(success: false, reason: .notFound)
        }
        guard row.usageCount < row.maxUsages else {
            return .init(success: false, reason: .usageExceeded)
        }
        try? await dataman.incrementUsage(id: row.id, on: req)
        return .init(success: true)
    }
}
