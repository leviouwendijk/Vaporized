import Foundation
import AsyncKit
import PostgresKit
import Vapor
import Surfaces
import Structures

@preconcurrency
public final class DatamanExecutor: DatamanDatabaseExecutor {
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
