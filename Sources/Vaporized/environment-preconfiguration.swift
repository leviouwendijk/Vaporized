import Foundation
import Vapor
import plate

// public protocol EnvironmentPreconfigurationKeyProtocol: RawRepresentable, CaseIterable, Sendable, Hashable where RawValue == String {
    // var environmentKey: String { get }

    // func infer() -> String
// }

// extension EnvironmentPreconfigurationKeyProtocol {
//     public func infer() -> String {
//         return self.rawValue
//             .snake()
//             .uppercased()
//     }
// }

private struct EnvironmentPreconfigurationKey<K>: StorageKey where K: EnvironmentExtractable {
    typealias Value = EnvironmentPreconfiguration<K>
}

public struct EnvironmentPreconfiguration<K>: Sendable where K: EnvironmentExtractable {
    private let app: Application
    private let keys: [K]
    private var storage: [K: String]

    public init(app: Application, keys: [K]) throws {
        self.app = app
        self.keys = keys
        self.storage = [:]

        self.storage = try validate()
        // try store() // this is recursive because init -> store() -> init -> store() ...
        app.storage[EnvironmentPreconfigurationKey<K>.self] = self
    }

    public init(app: Application) throws {
        try self.init(app: app, keys: Array(K.allCases))
    }

    public func validate() throws -> [K: String] {
        // Delegate lookup/validation to plate, keep Vaporized error surface
        do {
            return try keys.validate()
        } catch {
            // Log each missing/empty for clear diagnostics
            for k in keys {
                if (k.optionalValue()) == nil {
                    let name: String
                    switch k.key {
                    case .symbol(let s): name = s
                    case .auto:          name = k.infer()
                    }
                    app.standardLogger.error("Missing \(name) from app environment!")
                }
            }
            throw Abort(.internalServerError, reason: "Missing required environment variables")
        }
    }

    public func store() throws {
        let cfg = try Self(app: app, keys: keys)
        app.storage[EnvironmentPreconfigurationKey<K>.self] = cfg
    }

    public func value(_ key: K) -> String {
        storage[key]!
    }
}

extension Application {
    public func preconfiguration<K>(
        load type: K.Type
    ) -> EnvironmentPreconfiguration<K> where K: EnvironmentExtractable {
        guard let cfg = storage[EnvironmentPreconfigurationKey<K>.self] else {
            fatalError("""
                EnvironmentPreconfiguration<\(K.self)> not initialized; \
                make sure you called `try EnvironmentPreconfiguration(app:…, keys: …)` in configure(_:)`
            """)
        }
        return cfg
    }

    public func preconfigureEnvironment<K>(
        using type: K.Type,
        keys: [K] = Array(K.allCases)
    ) throws where K: EnvironmentExtractable {
        _ = try EnvironmentPreconfiguration<K>(app: self, keys: keys)
    }
}

// example implementation:
// public enum EnvironmentKeyObject: String, CaseIterable, Sendable, EnvironmentPreconfigurationKeyProtocol {
//     case myAPIKey  = "MY_API_KEY"
//     case someToken  = "EXAMPLE_TOKEN"
// }
