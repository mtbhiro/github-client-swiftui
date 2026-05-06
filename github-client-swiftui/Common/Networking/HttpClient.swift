import Foundation

nonisolated protocol HttpClient: Sendable {
    func send<T: Decodable & Sendable>(_ request: HttpRequest) async throws -> T
}

nonisolated struct HttpRequest: Sendable {
    let method: HttpMethod
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]

    init(
        method: HttpMethod = .get,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
    }
}

nonisolated enum HttpMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated enum HttpClientError: Error, Equatable {
    case invalidURL
    case httpError(statusCode: Int, data: Data)
    case decodingError
    case networkError(URLError)

    static func == (lhs: HttpClientError, rhs: HttpClientError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case let (.httpError(lCode, lData), .httpError(rCode, rData)):
            return lCode == rCode && lData == rData
        case (.decodingError, .decodingError):
            return true
        case let (.networkError(lError), .networkError(rError)):
            return lError.code == rError.code
        default:
            return false
        }
    }
}
