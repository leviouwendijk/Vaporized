import Foundation
import Vapor

public protocol EnvironmentPreconfigurationKeyProtocol: RawRepresentable, CaseIterable, Sendable, Hashable where RawValue == String {}

private struct EnvironmentPreconfigurationKey<K>: StorageKey

where K: EnvironmentPreconfigurationKeyProtocol {
    typealias Value = EnvironmentPreconfiguration<K>
}

public struct EnvironmentPreconfiguration<K>: Sendable
where K: EnvironmentPreconfigurationKeyProtocol
{
    private let app: Application
    private let keys: [K]
    private var storage: [K: String]

    public init(app: Application, keys: [K]) throws {
        self.app = app
        self.keys = keys
        self.storage = [:]

        let validated = try validate()
        self.storage = validated
        try store()
    }

    public init(app: Application) throws {
        try self.init(app: app, keys: Array(K.allCases))
    }

    public func validate() throws -> [K: String] {
        var dict = [K: String]()
        for key in keys {
            guard let val = Environment.get(key.rawValue), !val.isEmpty else {
                app.standardLogger.error("Missing \(key.rawValue) from app environment!")
                throw Abort(.internalServerError, reason: "Missing \(key.rawValue)")
            }
            dict[key] = val
        }
        return dict
    }

    public func store() throws {
        let cfg = try Self(app: app, keys: keys)
        app.storage[EnvironmentPreconfigurationKey<K>.self] = cfg
    }

    public func string(_ key: K) -> String {
        storage[key]!
    }
}

extension Application {
    public func environmentPreconfiguration<K>(
        _ type: K.Type
    ) -> EnvironmentPreconfiguration<K>
    where K: EnvironmentPreconfigurationKeyProtocol
    {
        guard let cfg = storage[EnvironmentPreconfigurationKey<K>.self] else {
            fatalError("""
                EnvironmentPreconfiguration<\(K.self)> not initialized; \
                make sure you called `try EnvironmentPreconfiguration(app:…, keys: …)` in configure(_:)`
            """)
        }
        return cfg
    }
}

// example implementation:
// public enum EnvironmentKeyObject: String, CaseIterable, Sendable, EnvironmentPreconfigurationKeyProtocol {
//     case myAPIKey  = "MY_API_KEY"
//     case someToken  = "EXAMPLE_TOKEN"
// }
