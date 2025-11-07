import Vapor
import Surfaces
import Structures
import Constructors

public extension DatamanSchemaLinter {
    static func lint<D: DatamanTransferableObject>(
        _ dto: D.Type,
        using client: DatamanClient,
        on req: Request
    ) async throws -> [DatamanSchemaLintIssue] {
        let expected = try D.psqlTypes()
        let actual   = try await fetchActualTypes(
            database: D.database,
            qualifiedTable: D.table,
            using: client,
            on: req
        )
        return compare(expected: expected, actual: actual)
    }
}

public struct DatamanSchemaLinter {
    // Map a Postgres type name to your PSQLType
    public static func pgTypeNameToPSQL(_ t: String, udtName: String?) -> PSQLType {
        let lower = t.lowercased()
        switch lower {
        case "integer", "int4": return .integer
        case "smallint", "int2": return .smallInt
        case "bigint", "int8": return .bigInt
        case "real", "float4": return .real
        case "double precision", "float8": return .doublePrecision
        case "numeric", "decimal": return .numeric(precision: nil, scale: nil)
        case "text": return .text
        case "character varying", "varchar": return .varchar(length: nil)
        case "character", "char": return .char(length: nil)
        case "boolean", "bool": return .boolean
        case "bytea": return .bytea
        case "uuid": return .uuid
        case "json": return .json
        case "jsonb": return .jsonb
        case "timestamp with time zone", "timestamptz": return .timestamptz
        case "timestamp without time zone", "timestamp": return .timestamp
        case "date": return .date
        case "time without time zone": return .time
        case "time with time zone": return .timeTZ
        default:
            // array types often arrive via udt_name like "_int4"
            if let u = udtName, u.hasPrefix("_") {
                let elem = String(u.dropFirst()) // e.g. "int4"
                return .array(of: pgTypeNameToPSQL(elem, udtName: nil))
            }
            return .custom(dbType: lower)
        }
    }

    // Split "schema.table" or fallback to "public"
    private static func split(_ qualified: String) -> (schema: String, table: String) {
        if let dot = qualified.firstIndex(of: ".") {
            let s = String(qualified[..<dot])
            let t = String(qualified[qualified.index(after: dot)...])
            return (s, t)
        }
        return ("public", qualified)
    }

    // Non-throwing JSON string extractor to keep call-sites clean
    @inline(__always)
    private static func string(_ obj: [String: JSONValue], _ key: String) -> String? {
        guard let v = obj[key] else { return nil }
        return try? v.stringValue
    }

    public static func fetchActualTypes(
        database: String,
        qualifiedTable: String,
        using client: DatamanClient,
        on req: Request
    ) async throws -> [String: PSQLType] {
        let (schema, table) = split(qualifiedTable)

        let criteria: JSONValue = .object([
            "$and": .array([
                .object(["table_schema": .object(["$eq": .string(schema)])]),
                .object(["table_name":   .object(["$eq": .string(table)])])
            ])
        ])

        let dr = DatamanRequest(
            operation: .fetch,
            database: database,
            table: "information_schema.columns",
            criteria: criteria,
            values: nil,
            fieldTypes: [
                "table_schema":     .text,
                "table_name":       .text,
                "column_name":      .text,
                "data_type":        .text,
                "udt_name":         .text,
                "ordinal_position": .integer
            ],
            order: .array([ .object(["ordinal_position": .string("asc")]) ]),
            limit: nil
        )

        let res = try await client.send(dr, on: req)
        guard let rows = res.results, !rows.isEmpty else {
            throw DatamanSchemaLintIssue.schemaNotFound(schema: schema, table: table)
        }

        var out: [String: PSQLType] = [:]

        // rows are JSONValue objects: {"column_name":"...", "data_type":"...", "udt_name":"..."}
        for j in rows {
            guard case let .object(obj) = j,
                  let col = string(obj, "column_name"),
                  let dt  = string(obj, "data_type")
            else { continue }

            let udt = string(obj, "udt_name")
            out[col] = pgTypeNameToPSQL(dt, udtName: udt)
        }
        return out
    }

    public static func compare(expected: [String: PSQLType], actual: [String: PSQLType]) -> [DatamanSchemaLintIssue] {
        var issues: [DatamanSchemaLintIssue] = []

        // extras in DTO (expected) not in DB
        for (k, v) in expected {
            if let a = actual[k] {
                if !equivalent(v, a) {
                    issues.append(.typeMismatch(name: k, expected: v, actual: a))
                }
            } else {
                issues.append(.extraColumn(name: k))
            }
        }
        // missing in DTO (exist in DB)
        for k in actual.keys where expected[k] == nil {
            issues.append(.missingColumn(name: k))
        }
        return issues
    }

    // Decide “equivalence” (e.g., varchar(n) ~ text?)
    private static func equivalent(_ lhs: PSQLType, _ rhs: PSQLType) -> Bool {
        switch (lhs, rhs) {
        case (.varchar, .text), (.text, .varchar): return true
        case let (.varchar(l), .varchar(r)): return (l == nil && r == nil) || (l == r)
        case let (.char(l), .char(r)):       return (l == nil && r == nil) || (l == r)
        case let (.numeric(lp, ls), .numeric(rp, rs)):
            return (lp ?? -1) == (rp ?? -1) && (ls ?? -1) == (rs ?? -1)
        case let (.array(of: le), .array(of: re)):
            return equivalent(le, re)
        default:
            return String(describing: lhs) == String(describing: rhs)
        }
    }
}
