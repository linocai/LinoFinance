public struct AppHealth: Codable, Equatable, Sendable {
    public let status: String
    public let app: String
    public let version: String
    public let environment: String

    public init(status: String, app: String, version: String, environment: String) {
        self.status = status
        self.app = app
        self.version = version
        self.environment = environment
    }
}
