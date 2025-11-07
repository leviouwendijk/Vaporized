import Vapor
import Structures
import Surfaces

public extension DatamanTransferableObjectQuery {
    /// Build → send → decode all rows
    static func fetchRows(
        _ criteria: JSONValue,
        order: JSONValue? = D.defaultOrder,
        limit: Int? = D.defaultLimit,
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await fetch(criteria: criteria, order: order, limit: limit)
        let res = try await client.send(dr, on: req)
        let rows = res.results ?? []
        return try rows.map(D.decodeRow)
    }

    /// Common case: first row
    static func fetchFirstRow(
        _ criteria: JSONValue,
        order: JSONValue? = D.defaultOrder,
        using client: DatamanClient,
        on req: Request
    ) async throws -> D.Row? {
        try await fetchRows(criteria, order: order, limit: 1, using: client, on: req).first
    }

    /// Create → optionally decode returning row(s)
    /// (Works if your server returns created rows; otherwise returns empty.)
    static func createAndDecode(
        values: [String: JSONValue],
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await create(values: values)
        let res = try await client.send(dr, on: req)
        let rows = res.results ?? []
        return try rows.map(D.decodeRow)
    }

    /// Update → optionally decode affected row(s), if server responds with rows
    static func updateAndDecode(
        criteria: JSONValue,
        values: [String: JSONValue],
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await update(criteria: criteria, values: values)
        let res = try await client.send(dr, on: req)
        let rows = res.results ?? []
        return try rows.map(D.decodeRow)
    }
}
