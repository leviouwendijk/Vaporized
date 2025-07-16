import Foundation
import Interfaces
import Surfaces
import Vapor

public enum APIKeyStyleError: Error, LocalizedError {
    case invalidHeaderName
}

public enum APIKeyStyle: String, CaseIterable, Sendable {
    case X_API_KEY             = "X-API-KEY"
    case x_api_key             = "x-api-key"
    case X_Api_Key             = "X-Api-Key"
    case API_KEY               = "API-KEY"
    case api_key               = "api-key"
    case Api_Key               = "Api-Key"
    case authorizationBearer   = "Authorization" 

    public var headerName: HTTPHeaders.Name? {
        switch self {
        case .authorizationBearer:
            return .authorization
        default:
            return HTTPHeaders.Name(self.rawValue)
        }
    }

    // public func bearerValue(apiKey: String) -> String {
    //     return "Bearer \(apiKey)"
    // }

    // public func headerValue(for apiKey: String) -> String {
    //     switch self {
    //     case .authorizationBearer:
    //         return bearerValue(apiKey: apiKey)
    //     default:
    //         return apiKey
    //     }
    // }

    // public func headerTuple(for apiKey: String) throws -> (name: HTTPHeaders.Name, value: String) {
    //     guard let name = headerName else { throw APIKeyStyleError.invalidHeaderName }
    //     return (name, headerValue(for: apiKey))
    // }

    // public func headers(for apiKey: String) throws -> HTTPHeaders {
    //     var headers = HTTPHeaders()
    //     let (name, value) = try headerTuple(for: apiKey)
    //     headers.add(name: name, value: value)
    //     return headers
    // }

    // public static func authorization(bearer: String) throws -> HTTPHeaders {
    //     let s = Self.self.authorizationBearer
    //     return try s.headers(for: bearer)
    // }

    public static func authorization(bearer token: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        return headers
    }
}
