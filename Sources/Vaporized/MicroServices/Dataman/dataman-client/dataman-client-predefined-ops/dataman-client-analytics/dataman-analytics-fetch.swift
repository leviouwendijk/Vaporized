import Foundation
import Vapor
import Structures
import Surfaces
import Extensions

// What we read back from Dataman for web.events (columns you actually store)
public struct WebEventRow: Codable, Sendable {
    public let id: Int64
    public let site_id: String
    public let occurred_at: String          // ISO from Dataman; parse to Date if you prefer
    public let visitor_id: String?
    public let session_id: String
    public let type: String

    public let url: String?
    public let ref: String?
    public let title: String?
    public let lang: String?
    public let ua: String?
    public let vp_w: Int?
    public let vp_h: Int?
    public let ms: Int?
    public let x: Double?
    public let y: Double?
    public let el: String?
    public let form_id: String?
    public let form_step: String?
    public let tz: String?
    public let dpr: Double?
    public let ok: Bool?
    public let raw: JSONValue?

    public let created_at: String
    public let url_path: String?
}

// Minimal operator helpers for Dataman criteria JSON.
private enum DMOp {
    static func eq(_ field: String, _ value: JSONValue) -> JSONValue { .object([field: .object(["$eq": value])]) }
    static func `in`(_ field: String, _ values: [JSONValue]) -> JSONValue { .object([field: .object(["$in": .array(values)])]) }
    static func between(_ field: String, _ a: JSONValue, _ b: JSONValue) -> JSONValue { .object([field: .object(["$between": .array([a,b])])]) }
    static func and(_ parts: [JSONValue]) -> JSONValue { .object(["$and": .array(parts)]) }
}

// Common bits for analytics DB/table
private enum DMAnalytics {
    static let db = "analytics"
    static let events = "web.events"
}

// MARK: - Core paging fetch

public struct EventsPage: Sendable {
    public let rows: [WebEventRow]
    public let hasMore: Bool
    /// Use this to continue (we page by last id ASC for stability).
    public let nextAfterId: Int64?
}

public extension DatamanClient {
    /// Fetch one page of events with stable ordering.
    func fetchEventsPage(
        siteId: String,
        from: Date,
        to: Date,
        types: [String]? = nil,         // e.g. ["pageview","heat_click"]
        urlPathPrefix: String? = nil,   // optional: filter a page subtree like "/artikelen/"
        afterId: Int64? = nil,          // for keyset pagination
        pageSize: Int = 2_000,
        on req: Request
    ) async throws -> EventsPage {
        var clauses: [JSONValue] = [
            DMOp.eq("site_id", .string(siteId)),
            DMOp.between("occurred_at", .string(from.postgresTimestamp), .string(to.postgresTimestamp))
        ]

        if let types, !types.isEmpty {
            clauses.append(DMOp.in("type", types.map(JSONValue.string)))
        }

        if let pfx = urlPathPrefix, !pfx.isEmpty {
            // cheap prefix using LIKE '...%'
            // Dataman criteria: { url_path: { $like: "/foo/%" } }
            clauses.append(.object(["url_path": .object(["$like": .string(pfx.hasSuffix("/") ? "\(pfx)%" : "\(pfx)/%")])]))
        }

        if let afterId {
            // clauses.append(.object(["id": .object(["$gt": .int64(afterId)])]))
            clauses.append(.object(["id": .object(["$gt": .int(Int(afterId))])]))
        }

        let criteria: JSONValue = DMOp.and(clauses)

        // order: id ASC for deterministic keyset paging
        let order: JSONValue = .array([ .object(["id": .string("asc")]) ])

        let reqBody = DatamanRequest(
            operation: .fetch,
            database: DMAnalytics.db,
            table: DMAnalytics.events,
            criteria: criteria,
            values: nil,
            fieldTypes: nil,
            order: order,
            limit: pageSize
        )

        let dmRes = try await send(reqBody, on: req)
        guard dmRes.success else {
            throw Abort(.badRequest, reason: dmRes.error ?? "Dataman fetch failed")
        }

        let rows: [WebEventRow] = try (dmRes.results ?? [])
            .map { try decode(WebEventRow.self, from: $0) }

        let nextAfterId = rows.last?.id
        return .init(rows: rows, hasMore: rows.count == pageSize, nextAfterId: nextAfterId)
    }

    /// Stream all events (paged) for a range. You can filter types and optional url path subtree.
    func streamEvents(
        siteId: String,
        from: Date,
        to: Date,
        types: [String]? = nil,
        urlPathPrefix: String? = nil,
        pageSize: Int = 2_000,
        on req: Request
    ) -> AsyncThrowingStream<WebEventRow, Error> {
        AsyncThrowingStream { continuation in
            // Detached is fine; no need to annotate the closure with @Sendable here
            Task.detached { 
                do {
                    var after: Int64? = nil
                    while true {
                        let page = try await fetchEventsPage(
                            siteId: siteId,
                            from: from,
                            to: to,
                            types: types,
                            urlPathPrefix: urlPathPrefix,
                            afterId: after,
                            pageSize: pageSize,
                            on: req
                        )
                        for row in page.rows { continuation.yield(row) }
                        guard page.hasMore, let next = page.nextAfterId else { break }
                        after = next
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Focused convenience wrappers

public extension DatamanClient {
    func fetchPageviews(
        siteId: String,
        from: Date, to: Date,
        on req: Request
    ) -> AsyncThrowingStream<WebEventRow, Error> {
        streamEvents(siteId: siteId, from: from, to: to, types: ["pageview"], on: req)
    }

    func fetchEngagedTime(
        siteId: String,
        from: Date, to: Date,
        on req: Request
    ) -> AsyncThrowingStream<WebEventRow, Error> {
        streamEvents(siteId: siteId, from: from, to: to, types: ["engaged_time"], on: req)
    }

    func fetchHeatClicks(
        siteId: String,
        pagePath: String,                 // exact page or subtree if you pass a prefix and set includeSubtree=true
        includeSubtree: Bool = false,
        from: Date, to: Date,
        on req: Request
    ) -> AsyncThrowingStream<WebEventRow, Error> {
        streamEvents(
            siteId: siteId,
            from: from, to: to,
            types: ["heat_click"],
            urlPathPrefix: includeSubtree ? pagePath : nil,
            on: req
        )
    }

    func fetchFormEvents(
        siteId: String,
        formId: String,                   // e.g. "#contact-form"
        from: Date, to: Date,
        on req: Request
    ) -> AsyncThrowingStream<WebEventRow, Error> {
        // filter types client-side after stream if you want multiple (start/step_view/submit/validation_error)
        streamEvents(siteId: siteId, from: from, to: to, types: ["form_start","form_step_view","form_submit","form_validation_error"], on: req)
            .filtering { $0.form_id == formId }
    }
}

// MARK: - Tiny decode/stream helpers

// private func iso8601(_ date: Date) -> String {
//     let f = ISO8601DateFormatter()
//     f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//     return f.string(from: date)
// }

private func decode<T: Decodable>(_ t: T.Type, from j: JSONValue) throws -> T {
    let data = try JSONEncoder().encode(j)
    return try JSONDecoder().decode(T.self, from: data)
}

private extension AsyncThrowingStream where Element == WebEventRow, Failure == Error {
    func filtering(_ pred: @Sendable @escaping (WebEventRow) -> Bool) -> AsyncThrowingStream<WebEventRow, Error> {
        AsyncThrowingStream { cont in
            Task.detached { 
                do {
                    for try await r in self where pred(r) { cont.yield(r) }
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
        }
    }
}
