import Vapor
import Structures
import Surfaces

public extension DatamanResponse {
    /// Decode response rows into a DTO's Row type using that DTO's decoding config.
    func rowsDecoded<D: DatamanTransferableObject>(_ dto: D.Type) throws -> [D.Row] {
        let rows = self.results ?? []
        return try rows.map(D.decodeRow)
    }
}

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
        return try res.rowsDecoded(D.self)
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

    // MARK: Create (legacy values)

    /// Create → optionally decode returning row(s) if server returns them
    static func createAndDecode(
        values: [String: JSONValue],
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await create(values: values)
        let res = try await client.send(dr, on: req)
        return try res.rowsDecoded(D.self)
    }

    // MARK: Create (payload)

    /// Create from strongly-typed payload → decode returning row(s) if present
    static func createAndDecode(
        payload: D.CreatePayload,
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await create(payload)
        let res = try await client.send(dr, on: req)
        return try res.rowsDecoded(D.self)
    }

    // MARK: Update (legacy values)

    /// Update → optionally decode affected row(s), if server responds with rows
    static func updateAndDecode(
        criteria: JSONValue,
        values: [String: JSONValue],
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await update(criteria: criteria, values: values)
        let res = try await client.send(dr, on: req)
        return try res.rowsDecoded(D.self)
    }

    // MARK: Update (payload)

    /// Update using strongly-typed payload → decode affected row(s) if present
    static func updateAndDecode(
        criteria: JSONValue,
        payload: D.UpdatePayload,
        using client: DatamanClient,
        on req: Request
    ) async throws -> [D.Row] {
        let dr  = try await update(criteria: criteria, payload: payload)
        let res = try await client.send(dr, on: req)
        return try res.rowsDecoded(D.self)
    }
}
