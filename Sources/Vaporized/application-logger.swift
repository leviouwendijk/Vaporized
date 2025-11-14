import Vapor
// import Interfaces
import plate

private struct LoggerKey: StorageKey { typealias Value = StandardLogger }
private struct AppNameKey: StorageKey { typealias Value = String }

public extension Application {
    var applicationName: String {
        get {
            storage[AppNameKey.self] ?? ProcessInfo.processInfo.processName
        }
        set {
            storage[AppNameKey.self] = newValue
        }
    }

    func configureStandardLogger(named name: String? = nil) {
        let loggerName = name ?? applicationName
        guard storage[LoggerKey.self] == nil else { return }
        do {
            let logger = try StandardLogger(for: loggerName)
            storage[LoggerKey.self] = logger
        } catch {
            fatalError("Could not initialize StandardLogger for \(loggerName): \(error)")
        }
    }

    var standardLogger: StandardLogger {
        guard let logger = storage[LoggerKey.self] else {
            fatalError("StandardLogger not configured. Call configureStandardLogger(named?:) first.")
        }
        return logger
    }
}
