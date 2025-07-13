import PostgresKit
import Structures

extension JSONValue {
    public func asPostgresData() -> PostgresData {
        switch self {
        case .string(let s):  return .init(string: s)
        case .int(let i):     return .init(int: i)
        case .double(let d):  return .init(double: d)
        case .bool(let b):    return .init(bool: b)
        case .null:           return .null
        default:              return .null
        }
    }
}
