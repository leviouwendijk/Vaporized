import Foundation
import Surfaces
import JWTKit

public struct CaptcherJWTPayload: JWTPayload, Codable, @unchecked Sendable {
    public let hashedToken: String
    public let ipAddress:   String
    public let maxUsages:   Int
    public let exp:         ExpirationClaim

    public init(
        hashedToken: String,
        ipAddress: String,
        maxUsages: Int,
        exp: ExpirationClaim
    ) {
        self.hashedToken = hashedToken
        self.ipAddress   = ipAddress
        self.maxUsages   = maxUsages
        self.exp         = exp
    }

    public func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}
