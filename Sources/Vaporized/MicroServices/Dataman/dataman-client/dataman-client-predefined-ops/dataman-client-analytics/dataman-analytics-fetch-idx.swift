import Foundation
import Vapor
import Structures
import Surfaces
import Extensions
import Constructors

private enum DMFT {
    static let db = "analytics"
    static let viewFirstTouch = "web.v_session_first_touch"
    static let viewFirstTouchInWindow = "web.v_first_touch_in_window" // ADD
}

private struct FirstTouchRow: Decodable, Sendable {
    let site_id: String
    let session_id: String
    let src: String
    let med: String
}


// window row (includes first_at in the view; we don't actually need to expose it here)
private struct FirstTouchWindowRow: Decodable, Sendable {
    let site_id: String
    let session_id: String
    let src: String?
    let med: String?
    // let first_at: Date?  // present in the view, not needed for the map
}

public extension DatamanClient {
    // /// Fetch first-touch (src/med) for a batch of session_ids using the materialized view.
    // func fetchFirstTouchForSessions(
    //     siteId: String,
    //     sessionIds: [String],
    //     on req: Request
    // ) async throws -> [String:(src:String, med:String)] {
    //     guard !sessionIds.isEmpty else { return [:] }

    //     let criteria: JSONValue = .object([
    //         "$and": .array([
    //             .object(["site_id": .object(["$eq": .string(siteId)])]),
    //             .object(["session_id": .object(["$in": .array(sessionIds.map(JSONValue.string))])])
    //         ])
    //     ])

    //     let order: JSONValue = .array([ .object(["session_id": .string("asc")]) ])

    //     let body = DatamanRequest(
    //         operation: .fetch,
    //         database: DMFT.db,
    //         table: DMFT.viewFirstTouch,
    //         criteria: criteria,
    //         values: nil,
    //         // fieldTypes: nil,
    //         fieldTypes: [
    //             "site_id":    .text,
    //             "session_id": .text,
    //             "src":        .text,
    //             "med":        .text
    //         ],
    //         order: order,
    //         limit: sessionIds.count
    //     )

    //     let dmRes = try await send(body, on: req)
    //     guard dmRes.success else {
    //         throw Abort(.badRequest, reason: dmRes.error ?? "Dataman fetch first-touch failed")
    //     }

    //     let rows: [FirstTouchRow] = try (dmRes.results ?? []).map { try decode(FirstTouchRow.self, from: $0) }
    //     var out: [String:(src:String,med:String)] = [:]
    //     out.reserveCapacity(rows.count)
    //     for r in rows { out[r.session_id] = (src: r.src, med: r.med) }
    //     return out
    // }

    // /// First-touch (src/med) per session.
    // /// 1) Prefer earliest web.events row with src/med present
    // /// 2) Fallback to web.v_session_first_touch for sessions still missing
    // func fetchFirstTouchForSessions(
    //     siteId: String,
    //     sessionIds: [String],
    //     on req: Request
    // ) async throws -> [String:(src:String, med:String)] {
    //     guard !sessionIds.isEmpty else { return [:] }

    //     var touch: [String:(src:String, med:String)] = [:]
    //     touch.reserveCapacity(sessionIds.count)

    //     // ---- (1) Try from flattened columns on web.events
    //     do {
    //         let criteria: JSONValue = .object([
    //             "$and": .array([
    //                 .object(["site_id":    .object(["$eq": .string(siteId)])]),
    //                 .object(["session_id": .object(["$in": .array(sessionIds.map(JSONValue.string))])]),
    //                 .object(["$or": .array([
    //                     .object(["src": .object(["$isnotnull": .bool(true)])]),
    //                     .object(["med": .object(["$isnotnull": .bool(true)])])
    //                 ])])
    //             ])
    //         ])
    //         let order: JSONValue = .array([
    //             .object(["session_id": .string("asc")]),
    //             .object(["occurred_at": .string("asc")])
    //         ])
    //         let body = DatamanRequest(
    //             operation: .fetch,
    //             database: "analytics",
    //             table: "web.events",
    //             criteria: criteria,
    //             values: nil,
    //             fieldTypes: [
    //                 "site_id":     .text,
    //                 "session_id":  .text,
    //                 "occurred_at": .timestamptz,
    //                 "src":         .text,
    //                 "med":         .text
    //             ],
    //             order: order,
    //             limit: nil
    //         )

    //         let dmRes = try await send(body, on: req)
    //         if dmRes.success, let rows = dmRes.results {
    //             struct Row: Decodable { let session_id: String; let src: String?; let med: String? }
    //             for r in rows {
    //                 if let data = try? JSONEncoder().encode(r),
    //                    let row  = try? JSONDecoder().decode(Row.self, from: data),
    //                    touch[row.session_id] == nil {
    //                     let s = (row.src?.isEmpty == false) ? row.src! : "direct"
    //                     let m = (row.med?.isEmpty == false) ? row.med! : "direct"
    //                     touch[row.session_id] = (s, m)
    //                 }
    //             }
    //         }
    //     }

    //     // ---- (2) Fallback to the DB view for any missing sessions
    //     let missing = sessionIds.filter { touch[$0] == nil }
    //     if !missing.isEmpty {
    //         // Existing view-based implementation (unchanged)
    //         let criteria: JSONValue = .object([
    //             "$and": .array([
    //                 .object(["site_id": .object(["$eq": .string(siteId)])]),
    //                 .object(["session_id": .object(["$in": .array(missing.map(JSONValue.string))])])
    //             ])
    //         ])
    //         let order: JSONValue = .array([ .object(["session_id": .string("asc")]) ])
    //         let body = DatamanRequest(
    //             operation: .fetch,
    //             database: "analytics",
    //             table: "web.v_session_first_touch",
    //             criteria: criteria,
    //             values: nil,
    //             fieldTypes: [
    //                 "site_id":    .text,
    //                 "session_id": .text,
    //                 "src":        .text,
    //                 "med":        .text
    //             ],
    //             order: order,
    //             limit: missing.count
    //         )

    //         let dmRes = try await send(body, on: req)
    //         guard dmRes.success else {
    //             throw Abort(.badRequest, reason: dmRes.error ?? "Dataman fetch first-touch (fallback) failed")
    //         }

    //         struct FirstTouchRow: Decodable { let session_id: String; let src: String; let med: String }
    //         let rows: [FirstTouchRow] = try (dmRes.results ?? []).map { try decode(FirstTouchRow.self, from: $0) }
    //         for r in rows { touch[r.session_id] = (r.src, r.med) }
    //     }

    //     return touch
    // }

    func fetchFirstTouchForSessions(
        siteId: String,
        sessionIds: [String],
        on req: Request
    ) async throws -> [String:(src:String, med:String)] {
        guard !sessionIds.isEmpty else { return [:] }

        var touch: [String:(src:String, med:String)] = [:]
        touch.reserveCapacity(sessionIds.count)

        // ---- (1) Prefer earliest web.events rows; filter src/med in Swift
        do {
            let criteria: JSONValue = .object([
                "$and": .array([
                    .object(["site_id":    .object(["$eq": .string(siteId)])]),
                    .object(["session_id": .object(["$in": .array(sessionIds.map(JSONValue.string))])])
                ])
            ])
            let order: JSONValue = .array([
                .object(["session_id":  .string("asc")]),
                .object(["occurred_at": .string("asc")])
            ])
            let body = DatamanRequest(
                operation: .fetch,
                database: "analytics",
                table: "web.events",
                criteria: criteria,
                values: nil,
                fieldTypes: [
                    "site_id":     .text,
                    "session_id":  .text,
                    "occurred_at": .timestamptz,
                    "src":         .text,
                    "med":         .text
                ],
                order: order,
                limit: nil
            )

            let dmRes = try await send(body, on: req)
            if dmRes.success, let rows = dmRes.results {
                struct Row: Decodable { let session_id: String; let src: String?; let med: String? }
                for r in rows {
                    guard touch.count < sessionIds.count else { break }
                    if let data = try? JSONEncoder().encode(r),
                       let row  = try? JSONDecoder().decode(Row.self, from: data),
                       touch[row.session_id] == nil {
                        // Only take rows that actually have src or med
                        if let s = row.src, !s.isEmpty {
                            touch[row.session_id] = (s, row.med ?? "direct")
                        } else if let m = row.med, !m.isEmpty {
                            touch[row.session_id] = ("direct", m)
                        }
                    }
                }
            }
        }

        // ---- (2) Fallback to the view for missing sessions
        let missing = sessionIds.filter { touch[$0] == nil }
        if !missing.isEmpty {
            let criteria: JSONValue = .object([
                "$and": .array([
                    .object(["site_id": .object(["$eq": .string(siteId)])]),
                    .object(["session_id": .object(["$in": .array(missing.map(JSONValue.string))])])
                ])
            ])
            let order: JSONValue = .array([ .object(["session_id": .string("asc")]) ])
            let body = DatamanRequest(
                operation: .fetch,
                database: DMFT.db,
                table: DMFT.viewFirstTouch,
                criteria: criteria,
                values: nil,
                fieldTypes: [
                    "site_id":    .text,
                    "session_id": .text,
                    "src":        .text,
                    "med":        .text
                ],
                order: order,
                limit: missing.count
            )

            let dmRes = try await send(body, on: req)
            guard dmRes.success else {
                throw Abort(.badRequest, reason: dmRes.error ?? "Dataman fetch first-touch (fallback) failed")
            }

            let rows: [FirstTouchRow] = try (dmRes.results ?? []).map { try decode(FirstTouchRow.self, from: $0) }
            for r in rows { touch[r.session_id] = (r.src, r.med) }
        }

        return touch
    }

    func fetchFirstTouchForWindow(
        siteId: String,
        from: Date,
        to: Date,
        on req: Request
    ) async throws -> [String:(src:String, med:String)] {
        // Local ISO8601 formatter (UTC, internet date-time)
        let fmt: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }()

        let criteria: JSONValue = .object([
            "$and": .array([
                .object(["site_id": .object(["$eq": .string(siteId)])]),
                .object(["first_at": .object([
                    "$between": .array([ .string(fmt.string(from: from)), .string(fmt.string(from: to)) ])
                ])])
            ])
        ])

        let order: JSONValue = .array([
            .object(["first_at": .string("asc")])
        ])

        let body = DatamanRequest(
            operation: .fetch,
            database: DMFT.db,
            table: DMFT.viewFirstTouchInWindow,
            criteria: criteria,
            values: nil,
            fieldTypes: [
                "site_id":    .text,
                "session_id": .text,
                "first_at":   .timestamptz,
                "src":        .text,
                "med":        .text
            ],
            order: order,
            limit: nil
        )

        let dmRes = try await send(body, on: req)
        guard dmRes.success else {
            throw Abort(.badGateway, reason: dmRes.error ?? "Dataman fetch first-touch (window) failed")
        }

        // Build the same map type you already use elsewhere
        var out: [String:(src:String, med:String)] = [:]
        out.reserveCapacity((dmRes.results ?? []).count)

        let rows: [FirstTouchWindowRow] = try (dmRes.results ?? []).map { try decode(FirstTouchWindowRow.self, from: $0) }
        for r in rows {
            let s = (r.src?.isEmpty == false) ? r.src! : "direct"
            let m = (r.med?.isEmpty == false) ? r.med! : "direct"
            out[r.session_id] = (s, m)
        }
        return out
    }
}
