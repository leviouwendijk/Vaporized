import Foundation
import Surfaces
import Vapor
import JWTKit

public struct StandardExpirationClaim: Sendable, Content {
    public let value: Date

    public init(value: Date) { self.value = value }

    public func verify(using signer: JWTSigner) throws {
        if value < Date() {
            throw JWTError.claimVerificationFailure(
                name: "exp", reason: "token is expired"
            )
        }
    }
}

public struct CaptcherJWTPayload: JWTPayload, Codable, Sendable, Content {
    public let hashedToken: String
    public let ipAddress:   String
    public let maxUsages:   Int
    public let exp:         StandardExpirationClaim

    public init(
        hashedToken: String,
        ipAddress: String,
        maxUsages: Int,
        exp: StandardExpirationClaim
    ) {
        self.hashedToken = hashedToken
        self.ipAddress   = ipAddress
        self.maxUsages   = maxUsages
        self.exp         = exp
    }

    public func verify(using signer: JWTSigner) throws {
        // try exp.verifyNotExpired()
        try exp.verify(using: signer)
    }
}
