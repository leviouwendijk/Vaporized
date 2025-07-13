import Surfaces
import Structures
import Vapor

// library: Structures
extension FieldValue: @retroactive Content { }
extension JSONValue: @retroactive Content { }

// surface: Dataman
extension DatamanRequest: @retroactive Content { }
extension DatamanResponse: @retroactive Content { }

// surface: Captcher
extension CaptcherTokenType: @retroactive Content {}
extension CaptcherOperation: @retroactive Content {}
extension CaptcherRequest: @retroactive Content {}
extension CaptcherResponse: @retroactive Content {}
extension CaptcherValidationResult: @retroactive Content {}
extension CaptcherValidateBody: @retroactive Content {}
