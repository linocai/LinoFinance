public enum APIEndpoint: Sendable {
    case health

    public var path: String {
        switch self {
        case .health:
            return "health"
        }
    }
}
