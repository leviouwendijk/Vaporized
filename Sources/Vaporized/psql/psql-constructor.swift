import AsyncKit
import PostgresKit
import Vapor
import Structures
import Surfaces

public struct PSQLQueryConstructor { }

extension PSQLQueryConstructor {
    public static func selectQuery(from request: DatamanRequest) -> PSQLQuery {
        let (whereSQL, params) = buildWhereClause(from: request)

        let orderSQL: String
        if let orderJSON = request.order {
            if let rawOrder = try? orderJSON.objectValue {
                let parts: [String] = rawOrder.compactMap { column, direction in
                    guard let dir = try? direction.stringValue else {
                        return nil
                    }
                    return "\(column) \(dir.uppercased())"
                }
                let joined = parts.joined(separator: ", ")
                orderSQL = joined.isEmpty
                  ? ""
                  : "ORDER BY \(joined)"
            } else {
                orderSQL = ""
            }
        } else {
            orderSQL = ""
        }

        let limitSQL = request.limit.map { "LIMIT \($0)" } ?? ""

        let sql = """
        SELECT row_to_json(t) AS json_row
          FROM \(request.table) t
        \(whereSQL)
        \(orderSQL)
        \(limitSQL);
        """
        return PSQLQuery(sql: sql, parameters: params)
    }

    public static func insertQuery(from request: DatamanRequest) -> PSQLQuery {
        guard let rawValues = try? request.values?.objectValue else {
            return PSQLQuery(sql: "", parameters: [])
        }
        let columns = Array(rawValues.keys).joined(separator: ", ")

        var placeholders: [String] = []
        var params: [PostgresData] = []

        for (i, col) in rawValues.keys.enumerated() {
            let idx = i + 1
            let castSuffix = request.fieldTypes?[col].map(PSQLType.typeCast) ?? ""
            placeholders.append("$\(idx)\(castSuffix)")
            params.append(rawValues[col]!.asPostgresData())
        }

        let phList = placeholders.joined(separator: ", ")
        let sql = """
        WITH inserted AS (
          INSERT INTO \(request.table)(\(columns))
          VALUES(\(phList))
          RETURNING *
        )
        SELECT row_to_json(inserted) AS json_row
          FROM inserted;
        """
        return PSQLQuery(sql: sql, parameters: params)
    }

    public static func updateQuery(from request: DatamanRequest) -> PSQLQuery {
        guard
            let rawValues = try? request.values?.objectValue,
            request.criteria != nil
        else {
            return PSQLQuery(sql: "", parameters: [])
        }

        var setClauses: [String] = []
        var params: [PostgresData] = []

        for (i, col) in rawValues.keys.enumerated() {
            let idx = i + 1
            let castSuffix = request.fieldTypes?[col].map(PSQLType.typeCast) ?? ""
            setClauses.append("\(col) = $\(idx)\(castSuffix)")
            params.append(rawValues[col]!.asPostgresData())
        }

        let (whereSQL, whereParams) = buildWhereClause(from: request, startIndex: rawValues.count + 1)
        params.append(contentsOf: whereParams)

        let sql = """
        UPDATE \(request.table)
        SET \(setClauses.joined(separator: ", "))
        \(whereSQL)
        RETURNING row_to_json(\(request.table)) AS json_row;
        """
        return PSQLQuery(sql: sql, parameters: params)
    }

    public static func deleteQuery(from request: DatamanRequest) -> PSQLQuery {
        let (whereSQL, params) = buildWhereClause(from: request)
        let sql = """
        DELETE FROM \(request.table)
        \(whereSQL)
        RETURNING row_to_json(\(request.table)) AS json_row;
        """
        return PSQLQuery(sql: sql, parameters: params)
    }

    // MARK: - Helpers

    // private static func buildWhereClause(
    //     from request: DatamanRequest,
    //     startIndex: Int = 1
    // ) -> (String, [PostgresData]) {
    //     guard let raw = try? request.criteria?.objectValue, !raw.isEmpty else {
    //         return ("", [])
    //     }
    //     var clauses: [String] = []
    //     var params: [PostgresData] = []

    //     for (i, key) in Array(raw.keys).enumerated() {
    //         let idx = startIndex + i
    //         let castSuffix = request.fieldTypes?[key].map(PSQLType.typeCast) ?? ""
    //         clauses.append("\(key) = $\(idx)\(castSuffix)")
    //         params.append(raw[key]!.asPostgresData())
    //     }
    //     return ("WHERE " + clauses.joined(separator: " AND "), params)
    // }

    private static func buildWhereClause(
        from request: DatamanRequest,
        startIndex: Int = 1
    ) -> (String, [PostgresData]) {
        guard let root = request.criteria else { return ("", []) }

        var params: [PostgresData] = []
        var next = startIndex

        func ph(_ data: PostgresData, cast: String? = nil) -> String {
            defer { next += 1 }
            params.append(data)
            return "$\(next)\(cast ?? "")"
        }

        // Convert JSONValue → SQL/params recursively
        func compile(_ node: JSONValue) throws -> String {
            if let obj = try? node.objectValue {
                // Logical combinators first
                if let andArray = obj["$and"], case .array(let parts) = andArray {
                    let compiled = try parts.map(compile).filter { !$0.isEmpty }
                    return compiled.isEmpty ? "" : "(" + compiled.joined(separator: " AND ") + ")"
                }
                if let orArray = obj["$or"], case .array(let parts) = orArray {
                    let compiled = try parts.map(compile).filter { !$0.isEmpty }
                    return compiled.isEmpty ? "" : "(" + compiled.joined(separator: " OR ") + ")"
                }

                // Field → operator-object or scalar
                var fragments: [String] = []

                for (field, value) in obj {
                    // operator-object?
                    if let opObj = try? value.objectValue {
                        // Optional per-field cast
                        let castSuffix = request.fieldTypes?[field].map(PSQLType.typeCast)

                        for (op, rhs) in opObj {
                            switch op {
                            case "$eq":
                                fragments.append("\(field) = \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$ne":
                                fragments.append("\(field) <> \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$gt":
                                fragments.append("\(field) > \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$gte":
                                fragments.append("\(field) >= \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$lt":
                                fragments.append("\(field) < \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$lte":
                                fragments.append("\(field) <= \(ph(rhs.asPostgresData(), cast: castSuffix))")
                            case "$between":
                                guard case .array(let arr) = rhs, arr.count == 2 else { continue }
                                let a = ph(arr[0].asPostgresData(), cast: castSuffix)
                                let b = ph(arr[1].asPostgresData(), cast: castSuffix)
                                fragments.append("\(field) BETWEEN \(a) AND \(b)")
                            case "$in":
                                guard case .array(let arr) = rhs, !arr.isEmpty else { fragments.append("FALSE"); continue }
                                let phs = arr.map { ph($0.asPostgresData(), cast: castSuffix) }.joined(separator: ", ")
                                fragments.append("\(field) IN (\(phs))")
                            case "$like":
                                fragments.append("\(field) LIKE \(ph(rhs.asPostgresData()))")
                            case "$ilike":
                                fragments.append("\(field) ILIKE \(ph(rhs.asPostgresData()))")
                            case "$is":
                                // expects null / true / false
                                if case .null = rhs { fragments.append("\(field) IS NULL") }
                                else { fragments.append("\(field) IS \(ph(rhs.asPostgresData()))") }
                            case "$not":
                                let inner = try compile(.object([field: rhs]))
                                if !inner.isEmpty { fragments.append("NOT (\(inner))") }
                            default:
                                // Unknown op → ignore to be safe
                                continue
                            }
                        }
                    } else {
                        // Bare equality: { "field": "value" }
                        let castSuffix = request.fieldTypes?[field].map(PSQLType.typeCast)
                        fragments.append("\(field) = \(ph(value.asPostgresData(), cast: castSuffix))")
                    }
                }

                return fragments.isEmpty ? "" : "(" + fragments.joined(separator: " AND ") + ")"
            }

            // Non-object at root: ignore (invalid)
            return ""
        }

        let whereSQL: String
        do {
            let sqlExpr = try compile(root)
            whereSQL = sqlExpr.isEmpty ? "" : "WHERE \(sqlExpr)"
        } catch {
            // On compile error, fall back to no WHERE (defensive)
            whereSQL = ""
            params.removeAll()
        }

        return (whereSQL, params)
    }
}
