import Vapor
import NIO
import Structures

public struct DatamanManagerKey: StorageKey {
    public typealias Value = DatamanPool
}

public extension Application {
    var datamanPool: DatamanPool {
        get {
            guard let mgr = self.storage[DatamanManagerKey.self] else {
                fatalError("DatamanPoolManager not configured; make sure configure(_:) and app.datamanPool = ... ran first")
            }
            return mgr
        }
        set { self.storage[DatamanManagerKey.self] = newValue }
    }
}

struct DatamanPoolShutdown: LifecycleHandler {
    let pool: DatamanPool
    func shutdown(_ application: Application) {
        pool.shutdown()
    }
}
