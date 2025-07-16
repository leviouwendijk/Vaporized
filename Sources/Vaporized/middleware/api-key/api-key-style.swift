import Foundation
import Interfaces
import Surfaces
import Vapor

public struct APIAuthorzationMethod: Sendable {
    public let style: APIKeyStyle
    public let token: String
    
    public init(
        style: APIKeyStyle,
        token: String
    ) {
        self.style = style
        self.token = token
    }

    public func headers() -> HTTPHeaders {
        var headers = HTTPHeaders()
        let headerName = style.headerName
        let headerValue = style.headerValue(for: token)
        headers.replaceOrAdd(name: headerName, value: headerValue)
        return headers
    }
}

public enum APIKeyStyle: String, CaseIterable, Sendable {
    case X_API_KEY             = "X-API-KEY"
    case x_api_key             = "x-api-key"
    case X_Api_Key             = "X-Api-Key"
    case API_KEY               = "API-KEY"
    case api_key               = "api-key"
    case Api_Key               = "Api-Key"
    case authorizationBearer   = "Authorization" 

    public var headerName: HTTPHeaders.Name {
        switch self {
        case .authorizationBearer:
            return .authorization
        default:
            return HTTPHeaders.Name(self.rawValue)
        }
    }

    public func bearerValue(apiKey: String) -> String {
        return "Bearer \(apiKey)"
    }

    public func headerValue(for apiKey: String) -> String {
        switch self {
        case .authorizationBearer:
            return bearerValue(apiKey: apiKey)
        default:
            return apiKey
        }
    }

    public static func authorization(bearer token: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.bearerAuthorization = BearerAuthorization(token: token)
        return headers
    }
}
