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

@preconcurrency
public final class DatamanExecutor<B: DatamanSQLBuilding>: DatamanDatabaseExecutor {
    private let datamanPool: DatamanPool
    public init(datamanPool: DatamanPool) { self.datamanPool = datamanPool }

    public func execute(request: DatamanRequest) async throws -> DatamanResponse {
        let pool = try datamanPool.pool(for: request.database)

        let rendered: PSQL.RenderedSQL = try {
            switch request.operation {
                case .fetch:  return try B.buildSelect(from: request)
                case .create: return try B.buildInsert(from: request)
                case .update: return try B.buildUpdate(from: request)
                case .delete: return try B.buildDelete(from: request)
            }
        }()

        let rows: [PostgresRow] = try await withCheckedThrowingContinuation { cont in
            pool.withConnection { conn in
                conn.query(rendered.sql, rendered.binds.map(PostgresData.initialize(fromPSQLBind:)))
                    .map(\.rows)
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

private extension PostgresData {
    static func initialize(fromPSQLBind b: PSQL.SQLBind) -> PostgresData {
        let data = (try? JSONEncoder().encode(b)) ?? Data("null".utf8)
        return PostgresData(string: String(data: data, encoding: .utf8) ?? "null")
    }
}
