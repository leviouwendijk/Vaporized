import Foundation
import PostgresKit

public struct PSQLQuery {
    public let sql: String
    public let parameters: [PostgresData]

    public init(sql: String, parameters: [PostgresData]) {
        self.sql = sql
        self.parameters = parameters
    }
}
