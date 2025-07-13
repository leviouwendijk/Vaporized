import Vapor
import FluentPostgresDriver

public struct PostgresConfigBuilder {
    public let host: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let caFile: String
    public let verification: CertificateVerification

    public init(
        host: String,
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        caFile: String,
        verification: CertificateVerification = .noHostnameVerification
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.caFile = caFile
        self.verification = verification
    }

    public func build() throws -> SQLPostgresConfiguration {
        let sslContext = try SSLContextPreinitializer(
            caFile: caFile,
            verification: verification
        ).sslContext

        return SQLPostgresConfiguration(
            hostname: host,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .require(sslContext)
        )
    }
}
