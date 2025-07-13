import Vapor

public extension Request {
    var clientIP: String {
        headers.first(name: .xForwardedFor) ?? remoteAddress?.ipAddress ?? "0.0.0.0" 
    }
}
