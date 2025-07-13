import Foundation
import Surfaces
import Vapor

public struct DatamanDatabase {
    public let database: DatabaseKey
    public let config: PostgresConfigBuilder
    
    public init(
        database: DatabaseKey,
        config: PostgresConfigBuilder
    ) {
        self.database = database
        self.config = config
    }
}
