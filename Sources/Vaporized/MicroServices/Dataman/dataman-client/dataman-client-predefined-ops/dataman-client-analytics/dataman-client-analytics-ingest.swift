import Foundation
import Vapor
import Surfaces
import Structures
import Extensions

public extension DatamanClient {
    func ingestAnalyticsBatch(
        _ env: Surfaces.AnalyzerCollectEnvelope,
        on req: Request
    ) async throws {
        let occurredAt = Date(timeIntervalSince1970: TimeInterval(env.ts) / 1000.0).postgresTimestamp

        let fieldTypes: [String: PSQLType] = [
            "site_id":     .text,
            "occurred_at": .timestamptz,
            "visitor_id":  .text,
            "session_id":  .text,
            "type":        .text,
            "url":         .text,
            "ref":         .text,
            "title":       .text,
            "lang":        .text,
            "ua":          .text,
            "vp_w":        .integer,
            "vp_h":        .integer,
            "ms":          .integer,
            "x":           .doublePrecision,
            "y":           .doublePrecision,
            "el":          .text,
            "form_id":     .text,
            "form_step":   .text,
            "tz":          .text,
            "dpr":         .doublePrecision,
            "ok":          .boolean,
            "raw":         .jsonb,

            "subdomain":  .text,
            "location":   .text,

            "src":        .text,
            "med":        .text,
            "campaign":   .text,
            "landing_path": .text
        ]

        for e in env.events {
            var row: [String: JSONValue] = [:]
            row["site_id"]     = .string(env.site_id)
            row["occurred_at"] = .string(occurredAt)
            row["visitor_id"]  = env.visitor_id.map(JSONValue.string) ?? .null
            row["session_id"]  = .string(env.session_id)
            row["type"]        = .string(e.type.rawValue)
            if let v = e.url   { row["url"]   = .string(v) }
            if let v = e.ref   { row["ref"]   = .string(v) }
            if let v = e.title { row["title"] = .string(v) }
            if let v = e.lang  { row["lang"]  = .string(v) }
            if let v = e.ua    { row["ua"]    = .string(v) }
            if let v = e.vp_w  { row["vp_w"]  = .int(v) }
            if let v = e.vp_h  { row["vp_h"]  = .int(v) }
            if let v = e.ms    { row["ms"]    = .int(v) }
            if let v = e.x     { row["x"]     = .double(v) }
            if let v = e.y     { row["y"]     = .double(v) }
            if let v = e.el    { row["el"]    = .string(v) }
            if let v = e.id    { row["form_id"]   = .string(v) }
            if let v = e.step  { row["form_step"] = .string(v) }
            if let v = e.tz    { row["tz"]    = .string(v) }
            if let v = e.dpr   { row["dpr"]   = .double(v) }
            if let v = e.ok    { row["ok"]    = .bool(v) }

            if let v = e.subdomain { row["subdomain"] = .string(v) }
            if let v = e.location  { row["location"]  = .string(v) }

            if let v = e.src          { row["src"]          = .string(v) }
            if let v = e.med          { row["med"]          = .string(v) }
            if let v = e.campaign     { row["campaign"]     = .string(v) }
            if let v = e.landing_path { row["landing_path"] = .string(v) }

            do {
                let rawData  = try JSONEncoder().encode(e)
                let rawValue = try JSONDecoder().decode(JSONValue.self, from: rawData)
                row["raw"]   = rawValue
            } catch {
                req.logger.warning("analytics raw encode failed: \(error)")
            }

            let dmReq = DatamanRequest(
                operation: .create,
                database:  "analytics",   
                table:     "web.events",      
                criteria:  nil,
                values:    .object(row),
                fieldTypes: fieldTypes,
                order:     nil,
                limit:     nil
            )

            _ = try await send(dmReq, on: req)
        }
    }
}
