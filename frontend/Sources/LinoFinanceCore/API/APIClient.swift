import Foundation

public final class APIClient {
    public let baseURL: URL
    public let authToken: String?
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        authToken: String? = nil,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.authToken = authToken?.isEmpty == false ? authToken : nil
        self.urlSession = urlSession
        self.decoder = decoder
    }

    public func health() async throws -> AppHealth {
        try await get(APIEndpoint.health)
    }

    private func get<Response: Decodable>(_ endpoint: APIEndpoint) async throws -> Response {
        let url = baseURL.appendingPathComponent(endpoint.path)
        var request = URLRequest(url: url)
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIClientError.badStatus(httpResponse.statusCode)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

public enum APIClientError: Error, Equatable {
    case invalidResponse
    case badStatus(Int)
}
