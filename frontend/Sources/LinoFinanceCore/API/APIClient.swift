import Foundation

public final class APIClient {
    public let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = decoder
    }

    public func health() async throws -> AppHealth {
        try await get(APIEndpoint.health)
    }

    private func get<Response: Decodable>(_ endpoint: APIEndpoint) async throws -> Response {
        let url = baseURL.appendingPathComponent(endpoint.path)
        let (data, response) = try await urlSession.data(from: url)

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

