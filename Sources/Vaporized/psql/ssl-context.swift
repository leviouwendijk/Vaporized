import NIOSSL

public struct SSLContextPreinitializer: Sendable {
    public let caFile: String
    public let verification: CertificateVerification
    public let sslContext: NIOSSLContext
    
    public init(
        caFile: String,
        verification: CertificateVerification = .noHostnameVerification
    ) throws {
        self.caFile = caFile
        self.verification = verification

        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = verification
        tlsConfig.trustRoots = .file(caFile)

        self.sslContext = try NIOSSLContext(configuration: tlsConfig)
    }
}
