import Foundation
import AsyncKit
import PostgresKit
import Vapor
import Surfaces
import Interfaces
import Structures
import Constructors

// @preconcurrency
// public final class DatamanExecutor: DatamanDatabaseExecutor {
@available(*, message: "Use the newer DatamanExecutor with dynamic builder instead.")
@preconcurrency
public final class LegacyDatamanExecutor: DatamanDatabaseExecutor {
    private let datamanPool: DatamanPool

    public init(datamanPool: DatamanPool) {
        self.datamanPool = datamanPool
    }

    public func execute(
        request: DatamanRequest
    ) async throws -> DatamanResponse {
        let pool = try datamanPool.pool(for: request.database)
        switch request.operation {
        case .fetch:
            return try await Self.handleFetch(request, pool: pool)
        case .create:
            return try await Self.handleCreate(request, pool: pool)
        case .update:
            return try await Self.handleUpdate(request, pool: pool)
        case .delete:
            return try await Self.handleDelete(request, pool: pool)
        }
    }

    private static func handleFetch(
        _ request: DatamanRequest,
        pool: EventLoopGroupConnectionPool<PostgresConnectionSource>
    ) async throws -> DatamanResponse {
        let query = PSQLQueryConstructor.selectQuery(from: request)
            
        let debugger = try StandardLogger(for: "Debugging")
        debugger.debug("[SQL] \(query.sql) -- \(query.parameters)")

        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(query.sql, query.parameters).map(\.rows)
            }.whenComplete { cont.resume(with: $0) }
        }
        let results = try rows.map { row -> JSONValue in
            let jsonString: String = try row.decode(String.self, file: "json_row")
            guard let data = jsonString.data(using: .utf8) else {
                throw Abort(.internalServerError, reason: "Bad JSON from database")
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        return DatamanResponse(success: true, results: results)
    }

    private static func handleCreate(
        _ request: DatamanRequest,
        pool: EventLoopGroupConnectionPool<PostgresConnectionSource>
    ) async throws -> DatamanResponse {
        let query = PSQLQueryConstructor.insertQuery(from: request)
        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(query.sql, query.parameters).map(\.rows)
            }.whenComplete { cont.resume(with: $0) }
        }
        let results = try rows.map { row -> JSONValue in
            let jsonString: String = try row.decode(String.self, file: "json_row")
            guard let data = jsonString.data(using: .utf8) else {
                throw Abort(.internalServerError, reason: "Bad JSON from database")
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        return DatamanResponse(success: true, results: results)
    }

    private static func handleUpdate(
        _ request: DatamanRequest,
        pool: EventLoopGroupConnectionPool<PostgresConnectionSource>
    ) async throws -> DatamanResponse {
        let query = PSQLQueryConstructor.updateQuery(from: request)
        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(query.sql, query.parameters).map(\.rows)
            }.whenComplete { cont.resume(with: $0) }
        }
        let results = try rows.map { row -> JSONValue in
            let jsonString: String = try row.decode(String.self, file: "json_row")
            guard let data = jsonString.data(using: .utf8) else {
                throw Abort(.internalServerError, reason: "Bad JSON from database")
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        return DatamanResponse(success: true, results: results)
    }

    private static func handleDelete(
        _ request: DatamanRequest,
        pool: EventLoopGroupConnectionPool<PostgresConnectionSource>
    ) async throws -> DatamanResponse {
        let query = PSQLQueryConstructor.deleteQuery(from: request)
        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(query.sql, query.parameters).map(\.rows)
            }.whenComplete { cont.resume(with: $0) }
        }
        let results = try rows.map { row -> JSONValue in
            let jsonString: String = try row.decode(String.self, file: "json_row")
            guard let data = jsonString.data(using: .utf8) else {
                throw Abort(.internalServerError, reason: "Bad JSON from database")
            }
            return try JSONDecoder().decode(JSONValue.self, from: data)
        }
        return DatamanResponse(success: true, results: results)
    }
}

public enum DatamanDebugEvent: Sendable {
    case building(request: DatamanRequest)
    case builtSQL(sql: String, binds: [PSQL.SQLBind])
    case queryStarted(sql: String, binds: [PostgresData])
    case queryFinished(durationMs: Int, rows: Int)
    case rowDecodeFailed(index: Int, error: Error)
    case producedResponse(rows: Int)
}

public typealias DatamanDebugSink = @Sendable (DatamanDebugEvent) -> Void

// @preconcurrency
// public final class DatamanExecutor<B: DatamanSQLBuilding>: DatamanDatabaseExecutor {
//     private let datamanPool: DatamanPool
//     public init(datamanPool: DatamanPool) { self.datamanPool = datamanPool }

//     public func execute(request: DatamanRequest) async throws -> DatamanResponse {
//         let pool = try datamanPool.pool(for: request.database)

//         let rendered: PSQL.RenderedSQL = try {
//             switch request.operation {
//                 case .fetch:  return try B.buildSelect(from: request)
//                 case .create: return try B.buildInsert(from: request)
//                 case .update: return try B.buildUpdate(from: request)
//                 case .delete: return try B.buildDelete(from: request)
//             }
//         }()

//         let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
//             pool.withConnection { conn in
//                 conn.query(rendered.sql, rendered.binds.map(PostgresData.initialize(fromPSQLBind:)))
//                     .map(\.rows)
//             }.whenComplete { cont.resume(with: $0) }
//         }

//         let results = try rows.map { row -> JSONValue in
//             let jsonString: String = try row.decode(String.self, file: "json_row")
//             guard let data = jsonString.data(using: .utf8) else {
//                 throw Abort(.internalServerError, reason: "Bad JSON from database")
//             }
//             return try JSONDecoder().decode(JSONValue.self, from: data)
//         }

//         return DatamanResponse(success: true, results: results)
//     }
// }

@preconcurrency
public final class DatamanExecutor<B: DatamanSQLBuilding>: DatamanDatabaseExecutor {
    private let datamanPool: DatamanPool
    private let debug: DatamanDebugSink?

    public init(
        datamanPool: DatamanPool,
        debug: DatamanDebugSink? = nil
    ) {
        self.datamanPool = datamanPool
        self.debug = debug
    }

    @inline(__always) private func emit(_ e: DatamanDebugEvent) {
        debug?(e)
    }

    public func execute(request: DatamanRequest) async throws -> DatamanResponse {
        let pool = try datamanPool.pool(for: request.database)

        emit(.building(request: request))

        // Build SQL via your builder
        let rendered: PSQL.RenderedSQL = try {
            let r: PSQL.RenderedSQL
            switch request.operation {
            case .fetch:  r = try B.buildSelect(from: request)
            case .create: r = try B.buildInsert(from: request)
            case .update: r = try B.buildUpdate(from: request)
            case .delete: r = try B.buildDelete(from: request)
            }
            return r
        }()
        emit(.builtSQL(sql: rendered.sql, binds: rendered.binds))

        // Map binds (your current JSON-encoding approach)
        let pgBinds: [PostgresData] = rendered.binds.map(PostgresData.initialize(fromPSQLBind:))
        emit(.queryStarted(sql: rendered.sql, binds: pgBinds))

        let t0 = DispatchTime.now()
        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(rendered.sql, pgBinds).map(\.rows)
            }.whenComplete { cont.resume(with: $0) }
        }
        let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0)
        emit(.queryFinished(durationMs: elapsedMs, rows: rows.count))

        // Decode rows -> JSONValue
        var out: [JSONValue] = []
        out.reserveCapacity(rows.count)

        for (i, row) in rows.enumerated() {
            do {
                let jsonString: String = try row.decode(String.self, file: "json_row")
                guard let data = jsonString.data(using: .utf8) else {
                    throw Abort(.internalServerError, reason: "Bad JSON from database")
                }
                let j = try JSONDecoder().decode(JSONValue.self, from: data)
                out.append(j)
            } catch {
                emit(.rowDecodeFailed(index: i, error: error))
                throw error
            }
        }

        emit(.producedResponse(rows: out.count))
        return DatamanResponse(success: true, results: out)
    }
}

// private extension PostgresData {
//     static func initialize(fromPSQLBind b: PSQL.SQLBind) -> PostgresData {
//         let data = (try? JSONEncoder().encode(b)) ?? Data("null".utf8)
//         return PostgresData(string: String(data: data, encoding: .utf8) ?? "null")
//     }
// }

private extension PostgresData {
    static func initialize(fromPSQLBind b: PSQL.SQLBind) -> PostgresData {
        let encoded = (try? JSONEncoder().encode(b)) ?? Data()
        if encoded.isEmpty { return .null }
        if let _ = try? JSONDecoder().decode(Optional<String>.self, from: encoded) as String? {
            if (try? JSONDecoder().decode(JSONNull.self, from: encoded)) != nil { return .null }
            if let s = try? JSONDecoder().decode(String.self, from: encoded) { return PostgresData(string: s) }
        }
        if let i = try? JSONDecoder().decode(Int.self, from: encoded) { return PostgresData(int: i) }
        if let d = try? JSONDecoder().decode(Double.self, from: encoded) { return PostgresData(double: d) }
        if let b = try? JSONDecoder().decode(Bool.self, from: encoded) { return PostgresData(bool: b) }

        // Fallback: bind as text (JSON object/array cases land here)
        return PostgresData(string: String(data: encoded, encoding: .utf8) ?? "null")
    }
}
private struct JSONNull: Decodable {}
