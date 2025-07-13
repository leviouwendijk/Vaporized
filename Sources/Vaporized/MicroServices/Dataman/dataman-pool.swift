import Vapor
import Structures
import Surfaces
import NIO               // EventLoopGroup
import NIOSSL            // TLS support
import FluentPostgresDriver  // SQLPostgresConfiguration
import PostgresKit           // PostgresConnectionSource & pool
import Extensions

public final class DatamanPool: @unchecked Sendable {
    public let pools: [DatabaseKey: EventLoopGroupConnectionPool<PostgresConnectionSource>]

    public init(
        eventLoopGroup: any EventLoopGroup,
        databases: [DatamanDatabase]
    ) throws {
        var dict: [DatabaseKey: EventLoopGroupConnectionPool<PostgresConnectionSource>] = [:]
        for entry in databases {
            let sqlConfig = try entry.config.build()
            let source    = PostgresConnectionSource(sqlConfiguration: sqlConfig)
            dict[entry.database] = EventLoopGroupConnectionPool(
                source: source,
                on: eventLoopGroup
            )
        }
        self.pools = dict
    }

    public func pool(
        for database: String
    ) throws -> EventLoopGroupConnectionPool<PostgresConnectionSource> {
        let key: DatabaseKey
        do {
            key = try DatabaseKey.parse(from: database)
        } catch let error as EnumParsingError {
            throw Abort(.badRequest, reason: error.localizedDescription)
        }
        guard let pool = pools[key] else {
            throw Abort(.internalServerError, reason: "No pool configured for \(key.rawValue)")
        }
        return pool
    }

    public func shutdown() {
        for pool in pools.values {
            try? pool.syncShutdownGracefully()
        }
    }
}
