import Foundation
import PostgresKit
import Constructors

extension PostgresData {
    /// Entry: prefer typed binds; otherwise fall back to erased-Encodable path.
    static func from(_ b: PSQL.SQLBind) -> PostgresData {
        if let v = b.value { return fromTyped(v, hint: b.hint) }
        return fromErasedEncodable(b)
    }

    /// Deterministic mapping for typed binds.
    private static func fromTyped(_ v: PSQL.SQLBindValue, hint: PSQLType?) -> PostgresData {
        switch v {
        case .null:
            return .null

        case .text(let s):
            return PostgresData(string: s)

        case .bool(let x):
            return PostgresData(bool: x)

        case .int64(let i):
            if let ii = Int(exactly: i) { return PostgresData(int: ii) }
            // too big for Int -> bind as text to avoid overflow
            return PostgresData(string: String(i))

        case .double(let d):
            return PostgresData(double: d)

        case .date(let d):
            // Policy: bind as ISO8601 text; SQL side casts with ::timestamptz
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
            f.timeZone = TimeZone(secondsFromGMT: 0)  // UTC
            return PostgresData(string: f.string(from: d))

        case .uuid(let u):
            return PostgresData(string: u.uuidString)

        case .decimal(let dec):
            // keep precision; cast using ::numeric in SQL if needed
            return PostgresData(string: dec.description)

        case .json(let data),
             .jsonb(let data):
            // Bind JSON as text; rely on ::json / ::jsonb in SQL if required
            return PostgresData(string: String(data: data, encoding: .utf8) ?? "null")

        case .bytea(let data):
            // Bind bytea as hex text (\xDEADBEEF...). Cast with ::bytea in SQL if needed.
            let hex = "\\x" + data.map { String(format: "%02x", $0) }.joined()
            return PostgresData(string: hex)

        case .inet(let s):
            return PostgresData(string: s) // cast with ::inet at SQL level when appropriate

        case .array(let items, let element):
            // Render a PG array literal. Quote text/complex elements; NULL stays unquoted.
            let body = items.map { item -> String in
                switch item {
                case .null:
                    return "NULL"
                case .text(let s):
                    // escape internal quotes
                    return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
                case .int64(let i):
                    return String(i)
                case .double(let d):
                    return String(d)
                case .bool(let b):
                    return b ? "t" : "f"
                default:
                    // For mixed/complex, map the element using fromTyped and quote its textual form
                    let v = PostgresData.fromTyped(item, hint: element).string ?? "null"
                    return "\"\(v.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
            }.joined(separator: ",")
            // Note: the array type cast belongs in SQL, not the literal. Return literal here.
            return PostgresData(string: "{\(body)}")
        }
    }

    /// Robust fallback for erased-Encodable binds:
    /// JSON-encode once; try primitives; else bind JSON text.
    private static func fromErasedEncodable(_ bind: PSQL.SQLBind) -> PostgresData {
        return initialize(fromPSQLBind: bind)
    }
}

extension PostgresData {
    /// JSON round-trip bridge for legacy `Encodable` binds.
    static func initialize(fromPSQLBind bind: PSQL.SQLBind) -> PostgresData {
        // 1) Encode once with ISO8601 dates
        let enc = JSONEncoder()
        // if #available(macOS 10.12, *) {
        //     enc.dateEncodingStrategy = .iso8601

        if #available(macOS 10.12, *) {
            enc.dateEncodingStrategy = .custom { date, encoder in
                let f = ISO8601DateFormatter()
                f.formatOptions = [
                    .withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone,
                ]
                f.timeZone = TimeZone(secondsFromGMT: 0)  // UTC
                var c = encoder.singleValueContainer()
                try c.encode(f.string(from: date))
            }
        } else {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .iso8601)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
            enc.dateEncodingStrategy = .formatted(f)
        }

        let data: Data
        do {
            data = try enc.encode(bind)
        } catch {
            // expose encoding failure as visible text instead of silent NULL
            return PostgresData(string: #"{"_bind_encode_error":"\#(String(describing: error))"}"#)
        }
        if data.isEmpty { return .null }

        // 2) Primitive attempts (strict order)
        let dec = JSONDecoder()
        if #available(macOS 10.12, *) {
            dec.dateDecodingStrategy = .iso8601
        }

        if let v = try? dec.decode(String.self, from: data) { return PostgresData(string: v) }
        if let v = try? dec.decode(Bool.self,   from: data) { return PostgresData(bool: v) }
        if let v = try? dec.decode(Int.self,    from: data) { return PostgresData(int: v) }
        if let v = try? dec.decode(Int64.self,  from: data) {
            if let i = Int(exactly: v) { return PostgresData(int: i) }
            return PostgresData(string: String(v))
        }
        if let v = try? dec.decode(Double.self, from: data) { return PostgresData(double: v) }

        // 3) explicit JSON null?
        if data.count == 4 && data.elementsEqual(Data("null".utf8)) { return .null }

        // 4) Fallback: arrays/objects as JSON text
        let jsonString = String(data: data, encoding: .utf8) ?? "null"
        return PostgresData(string: jsonString)
    }
}
