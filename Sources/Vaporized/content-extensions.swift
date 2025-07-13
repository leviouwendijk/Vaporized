import Surfaces
import Vapor

// Dataman
extension DatamanRequest: @retroactive Content { }
extension DatamanResponse: @retroactive Content { }

// Captcher
extension CaptcherTokenType: @retroactive Content {}
extension CaptcherOperation: @retroactive Content {}
extension CaptcherRequest: @retroactive Content {}
extension CaptcherResponse: @retroactive Content {}
extension CaptcherValidationResult: @retroactive Content {}
