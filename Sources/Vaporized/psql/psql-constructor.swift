import AsyncKit
import PostgresKit
import Vapor
import Structures
import Surfaces

public struct PSQLQueryConstructor { }

extension PSQLQueryConstructor {
    // public static func selectQuery(from request: DatamanRequest) -> PSQLQuery {
    //     let (whereSQL, params) = buildWhereClause(from: request)
    //     let limit = request.limit.map { "LIMIT \($0)" } ?? ""
    //     let sql = """
    //     SELECT row_to_json(t) AS json_row
    //       FROM \(request.table) t
    //     \(whereSQL)
    //     \(limit);
    //     """
    //     return PSQLQuery(sql: sql, parameters: params)
    // }

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

    private static func buildWhereClause(
        from request: DatamanRequest,
        startIndex: Int = 1
    ) -> (String, [PostgresData]) {
        guard let raw = try? request.criteria?.objectValue, !raw.isEmpty else {
            return ("", [])
        }
        var clauses: [String] = []
        var params: [PostgresData] = []

        for (i, key) in Array(raw.keys).enumerated() {
            let idx = startIndex + i
            let castSuffix = request.fieldTypes?[key].map(PSQLType.typeCast) ?? ""
            clauses.append("\(key) = $\(idx)\(castSuffix)")
            params.append(raw[key]!.asPostgresData())
        }
        return ("WHERE " + clauses.joined(separator: " AND "), params)
    }
}
