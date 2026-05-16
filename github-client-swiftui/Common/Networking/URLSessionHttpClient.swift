import Foundation

nonisolated struct URLSessionHttpClient: HttpClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.session = session
        self.decoder = decoder
    }

    func send<T: Decodable & Sendable>(_ request: HttpRequest) async throws -> T {
        let urlRequest = try buildURLRequest(from: request)

        try Task.checkCancellation()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }
            throw HttpClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HttpClientError.networkError(URLError(.badServerResponse))
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HttpClientError.httpError(
                statusCode: httpResponse.statusCode,
                data: data,
                headers: Self.headerMap(from: httpResponse)
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HttpClientError.decodingError
        }
    }

    private func buildURLRequest(from request: HttpRequest) throws -> URLRequest {
        let baseURL = request.host.baseURL
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HttpClientError.invalidURL
        }
        components.path = request.path
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }

        guard let url = components.url else {
            throw HttpClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        for (key, value) in request.host.defaultHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        return urlRequest
    }

    private static func headerMap(from response: HTTPURLResponse) -> [String: String] {
        var map: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let keyString = key as? String, let valueString = value as? String else { continue }
            map[keyString] = valueString
        }
        return map
    }
}
