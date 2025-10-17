import Foundation
import Vapor
import Structures
import Surfaces
import Extensions

private enum DMFT {
    static let db = "analytics"
    static let viewFirstTouch = "web.v_session_first_touch"
}

private struct FirstTouchRow: Decodable, Sendable {
    let site_id: String
    let session_id: String
    let src: String
    let med: String
}

public extension DatamanClient {
    /// Fetch first-touch (src/med) for a batch of session_ids using the materialized view.
    func fetchFirstTouchForSessions(
        siteId: String,
        sessionIds: [String],
        on req: Request
    ) async throws -> [String:(src:String, med:String)] {
        guard !sessionIds.isEmpty else { return [:] }

        let criteria: JSONValue = .object([
            "$and": .array([
                .object(["site_id": .object(["$eq": .string(siteId)])]),
                .object(["session_id": .object(["$in": .array(sessionIds.map(JSONValue.string))])])
            ])
        ])

        let order: JSONValue = .array([ .object(["session_id": .string("asc")]) ])

        let body = DatamanRequest(
            operation: .fetch,
            database: DMFT.db,
            table: DMFT.viewFirstTouch,
            criteria: criteria,
            values: nil,
            fieldTypes: nil,
            order: order,
            limit: sessionIds.count
        )

        let dmRes = try await send(body, on: req)
        guard dmRes.success else {
            throw Abort(.badRequest, reason: dmRes.error ?? "Dataman fetch first-touch failed")
        }

        let rows: [FirstTouchRow] = try (dmRes.results ?? []).map { try decode(FirstTouchRow.self, from: $0) }
        var out: [String:(src:String,med:String)] = [:]
        out.reserveCapacity(rows.count)
        for r in rows { out[r.session_id] = (src: r.src, med: r.med) }
        return out
    }
}
