import Foundation
import Constructors

public enum DatamanSchemaLintIssue: Error, LocalizedError, Sendable, CustomStringConvertible {
    case missingColumn(name: String)      // in DB, not in DTO — or vice-versa depending on perspective
    case extraColumn(name: String)        // in DTO, not in DB
    case typeMismatch(name: String, expected: PSQLType, actual: PSQLType)
    case schemaNotFound(schema: String, table: String)

    public var errorDescription: String? {
        switch self {
        case .missingColumn(let n):
            return "Missing column: \(n)"
        case .extraColumn(let n):
            return "Extra column: \(n)"
        case .typeMismatch(let n, let e, let a):
            return "Type mismatch for \(n): expected \(String(describing: e)), actual \(String(describing: a))"
        case .schemaNotFound(let s, let t):
            return "Table not found: \(s).\(t)"
        }
    }

    public var failureReason: String? {
        switch self {
        case .missingColumn(let n):
            return "The database table does not contain the required column “\(n)”."
        case .extraColumn(let n):
            return "The DTO defines a column “\(n)” that is not present in the database."
        case .typeMismatch(_, let e, let a):
            return "The database type \(String(describing: a)) does not match the DTO’s expected type \(String(describing: e))."
        case .schemaNotFound(let s, let t):
            return "No rows were returned from information_schema for \(s).\(t)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .missingColumn(let n):
            return "Add the column “\(n)” to the table, or remove/adjust it in the DTO if it is not required."
        case .extraColumn(let n):
            return "Drop the DTO field “\(n)” or add the corresponding column to the table."
        case .typeMismatch(let n, let e, let a):
            return "Align the types for “\(n)”: migrate the table to \(String(describing: e)) or update the DTO to \(String(describing: a))."
        // case .schemaNotFound(let s, let t):
        case .schemaNotFound(_ ,_ ):
            return "Verify the database name, schema, and table; ensure the table exists and that the querying role has access."
        }
    }

    public var description: String {
        let parts = [errorDescription, failureReason, recoverySuggestion].compactMap { $0 }
        return parts.joined(separator: "\n\n")
    }
}
