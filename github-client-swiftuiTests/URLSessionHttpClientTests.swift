import Foundation
import Testing
@testable import github_client_swiftui

struct URLSessionHttpClientTests {

    // MARK: - Test Helpers

    private struct SampleResponse: Decodable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    private func makeSUT() -> (client: URLSessionHttpClient, stub: StubURLProtocol.Type) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = URLSessionHttpClient(session: session)
        return (client, StubURLProtocol.self)
    }

    // MARK: - Success

    @Test func send_success_decodesResponse() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"swift"}"#.data(using: .utf8)!
        stub.stub(data: json, statusCode: 200)

        let request = HttpRequest(path: "/search/repositories", queryItems: [
            URLQueryItem(name: "q", value: "swift"),
        ])
        let result: SampleResponse = try await client.send(request)

        #expect(result == SampleResponse(id: 1, name: "swift"))
    }

    // MARK: - HTTP Error

    @Test func send_httpError_throwsHttpError() async throws {
        let (client, stub) = makeSUT()
        let body = #"{"message":"rate limit exceeded"}"#.data(using: .utf8)!
        stub.stub(data: body, statusCode: 403)

        let request = HttpRequest(path: "/search/repositories")

        await #expect(throws: HttpClientError.httpError(statusCode: 403, data: body)) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    @Test func send_serverError_throwsHttpError() async throws {
        let (client, stub) = makeSUT()
        let body = Data()
        stub.stub(data: body, statusCode: 500)

        let request = HttpRequest(path: "/repos/owner/repo")

        await #expect(throws: HttpClientError.httpError(statusCode: 500, data: body)) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    // MARK: - Decoding Error

    @Test func send_invalidJSON_throwsDecodingError() async throws {
        let (client, stub) = makeSUT()
        let invalidJSON = #"{"invalid": true}"#.data(using: .utf8)!
        stub.stub(data: invalidJSON, statusCode: 200)

        let request = HttpRequest(path: "/search/repositories")

        await #expect(throws: HttpClientError.decodingError) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    // MARK: - Network Error

    @Test func send_networkError_throwsNetworkError() async throws {
        let (client, stub) = makeSUT()
        stub.stub(error: URLError(.notConnectedToInternet))

        let request = HttpRequest(path: "/search/repositories")

        await #expect(throws: HttpClientError.networkError(URLError(.notConnectedToInternet))) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    // MARK: - Cancellation

    @Test func send_cancelled_throwsCancellationError() async throws {
        let (client, stub) = makeSUT()
        stub.stub(data: Data(), statusCode: 200, delay: 5.0)

        let request = HttpRequest(path: "/search/repositories")

        let task = Task<SampleResponse, Error> {
            try await client.send(request)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            Issue.record("Expected cancellation error")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }

    // MARK: - Request Construction

    @Test func send_constructsCorrectURL() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.stub(data: json, statusCode: 200)

        var capturedRequest: URLRequest?
        stub.onRequest = { capturedRequest = $0 }

        let request = HttpRequest(
            path: "/search/repositories",
            queryItems: [
                URLQueryItem(name: "q", value: "swift"),
                URLQueryItem(name: "page", value: "2"),
            ]
        )
        let _: SampleResponse = try await client.send(request)

        let url = try #require(capturedRequest?.url)
        #expect(url.scheme == "https")
        #expect(url.host == "api.github.com")
        #expect(url.path == "/search/repositories")

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = try #require(components?.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "q", value: "swift")))
        #expect(queryItems.contains(URLQueryItem(name: "page", value: "2")))
    }

    @Test func send_includesCustomHeaders() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.stub(data: json, statusCode: 200)

        var capturedRequest: URLRequest?
        stub.onRequest = { capturedRequest = $0 }

        let request = HttpRequest(
            path: "/user",
            headers: ["Authorization": "Bearer token123"]
        )
        let _: SampleResponse = try await client.send(request)

        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }

    @Test func send_includesAcceptHeader() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.stub(data: json, statusCode: 200)

        var capturedRequest: URLRequest?
        stub.onRequest = { capturedRequest = $0 }

        let request = HttpRequest(path: "/repos")
        let _: SampleResponse = try await client.send(request)

        #expect(capturedRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3+json")
    }

    @Test func send_usesCorrectHTTPMethod() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.stub(data: json, statusCode: 200)

        var capturedRequest: URLRequest?
        stub.onRequest = { capturedRequest = $0 }

        let request = HttpRequest(method: .post, path: "/repos")
        let _: SampleResponse = try await client.send(request)

        #expect(capturedRequest?.httpMethod == "POST")
    }
}

// MARK: - StubURLProtocol

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var stubbedData: Data?
    nonisolated(unsafe) static var stubbedStatusCode: Int = 200
    nonisolated(unsafe) static var stubbedError: Error?
    nonisolated(unsafe) static var stubbedDelay: TimeInterval = 0
    nonisolated(unsafe) static var onRequest: ((URLRequest) -> Void)?

    static func stub(
        data: Data? = nil,
        statusCode: Int = 200,
        error: Error? = nil,
        delay: TimeInterval = 0
    ) {
        stubbedData = data
        stubbedStatusCode = statusCode
        stubbedError = error
        stubbedDelay = delay
        onRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.onRequest?(request)

        if Self.stubbedDelay > 0 {
            Thread.sleep(forTimeInterval: Self.stubbedDelay)
        }

        if let error = Self.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.stubbedStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = Self.stubbedData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
