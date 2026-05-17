import Foundation
import os
import Testing
@testable import github_client_swiftui

struct URLSessionHttpClientTests {

    // MARK: - Test Helpers

    private struct SampleResponse: Decodable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    private func makeSUT() -> (client: URLSessionHttpClient, stub: StubURLProtocol.Handle) {
        let stub = StubURLProtocol.register()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = URLSessionHttpClient(session: session)
        return (client, stub)
    }

    // MARK: - Success

    @Test func send_success_decodesResponse() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"swift"}"#.data(using: .utf8)!
        stub.respond(data: json, statusCode: 200)

        let request = HttpRequest(host: stub.apiHost, path: "/search/repositories", queryItems: [
            URLQueryItem(name: "q", value: "swift"),
        ])
        let result: SampleResponse = try await client.send(request)

        #expect(result == SampleResponse(id: 1, name: "swift"))
    }

    // MARK: - HTTP Error

    @Test func send_httpError_throwsHttpError() async throws {
        let (client, stub) = makeSUT()
        let body = #"{"message":"rate limit exceeded"}"#.data(using: .utf8)!
        stub.respond(data: body, statusCode: 403)

        let request = HttpRequest(host: stub.apiHost, path: "/search/repositories")

        await #expect {
            let _: SampleResponse = try await client.send(request)
        } throws: { error in
            guard case let HttpClientError.httpError(statusCode, data, _) = error else { return false }
            return statusCode == 403 && data == body
        }
    }

    @Test func send_serverError_throwsHttpError() async throws {
        let (client, stub) = makeSUT()
        let body = Data()
        stub.respond(data: body, statusCode: 500)

        let request = HttpRequest(host: stub.apiHost, path: "/repos/owner/repo")

        await #expect {
            let _: SampleResponse = try await client.send(request)
        } throws: { error in
            guard case let HttpClientError.httpError(statusCode, data, _) = error else { return false }
            return statusCode == 500 && data == body
        }
    }

    @Test func send_httpError_includesResponseHeaders() async throws {
        let (client, stub) = makeSUT()
        let body = #"{"message":"forbidden"}"#.data(using: .utf8)!
        stub.respond(data: body, statusCode: 403, headers: [
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": "1700000000",
        ])

        let request = HttpRequest(host: stub.apiHost, path: "/search/repositories")

        await #expect {
            let _: SampleResponse = try await client.send(request)
        } throws: { error in
            guard case let HttpClientError.httpError(_, _, headers) = error else { return false }
            return headers["X-RateLimit-Remaining"] == "0"
                && headers["X-RateLimit-Reset"] == "1700000000"
        }
    }

    // MARK: - Decoding Error

    @Test func send_invalidJSON_throwsDecodingError() async throws {
        let (client, stub) = makeSUT()
        let invalidJSON = #"{"invalid": true}"#.data(using: .utf8)!
        stub.respond(data: invalidJSON, statusCode: 200)

        let request = HttpRequest(host: stub.apiHost, path: "/search/repositories")

        await #expect(throws: HttpClientError.decodingError) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    // MARK: - Network Error

    @Test func send_networkError_throwsNetworkError() async throws {
        let (client, stub) = makeSUT()
        stub.respond(error: URLError(.notConnectedToInternet))

        let request = HttpRequest(host: stub.apiHost, path: "/search/repositories")

        await #expect(throws: HttpClientError.networkError(URLError(.notConnectedToInternet))) {
            let _: SampleResponse = try await client.send(request)
        }
    }

    // MARK: - Cancellation

    @Test func send_cancelled_throwsCancellationError() async throws {
        let (client, stub) = makeSUT()
        stub.respond(data: Data(), statusCode: 200, delay: 5.0)

        let host = stub.apiHost
        let task = Task<SampleResponse, Error> {
            let request = HttpRequest(host: host, path: "/search/repositories")
            return try await client.send(request)
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

    @Test func send_constructsCorrectURL_forGitHubHost() async throws {
        // ホスト差し替えを伴わない URL 構築のテスト。production の .github を直接使う。
        // 実際の HTTP リクエストは StubURLProtocol で受け取れないため、
        // protocolClasses を絞らない session を使い、URLProtocol で URL だけ捕捉する。
        let captureStub = StubURLProtocol.register(host: "api.github.com")
        defer { StubURLProtocol.unregister(captureStub) }
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        captureStub.respond(data: json, statusCode: 200)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = URLSessionHttpClient(session: session)

        let request = HttpRequest(
            host: .github,
            path: "/search/repositories",
            queryItems: [
                URLQueryItem(name: "q", value: "swift"),
                URLQueryItem(name: "page", value: "2"),
            ]
        )
        let _: SampleResponse = try await client.send(request)

        let url = try #require(captureStub.lastRequest?.url)
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
        stub.respond(data: json, statusCode: 200)

        let request = HttpRequest(
            host: stub.apiHost,
            path: "/user",
            headers: ["Authorization": "Bearer token123"]
        )
        let _: SampleResponse = try await client.send(request)

        #expect(stub.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }

    @Test func send_includesAcceptHeader() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.respond(data: json, statusCode: 200)

        let request = HttpRequest(host: stub.apiHost, path: "/repos")
        let _: SampleResponse = try await client.send(request)

        #expect(stub.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3+json")
    }

    @Test func send_usesCorrectHTTPMethod() async throws {
        let (client, stub) = makeSUT()
        let json = #"{"id":1,"name":"test"}"#.data(using: .utf8)!
        stub.respond(data: json, statusCode: 200)

        let request = HttpRequest(host: stub.apiHost, method: .post, path: "/repos")
        let _: SampleResponse = try await client.send(request)

        #expect(stub.lastRequest?.httpMethod == "POST")
    }
}

// MARK: - StubURLProtocol

/// URLSession に差し込むテスト用 URLProtocol。
///
/// テストごとに固有のホスト ("test-{UUID}.invalid" または明示指定) を払い出し、
/// `Handle` 経由でそのホストに対する応答だけを設定する。
/// プロセス全体で 1 つの registry を持つが、key はテストごとに分離されているため
/// 並列実行下でもレースは発生しない。
final class StubURLProtocol: URLProtocol {

    struct Responder: Sendable {
        var data: Data?
        var statusCode: Int = 200
        var error: (any Error)?
        var delay: TimeInterval = 0
        var headers: [String: String] = [:]
        var lastRequest: URLRequest?
    }

    final class Handle: Sendable {
        let host: String
        var apiHost: ApiHost { .custom(URL(string: "https://\(host)")!) }

        init(host: String) {
            self.host = host
        }

        func respond(
            data: Data? = nil,
            statusCode: Int = 200,
            error: (any Error)? = nil,
            delay: TimeInterval = 0,
            headers: [String: String] = [:]
        ) {
            Registry.shared.update(host: host) { responder in
                responder.data = data
                responder.statusCode = statusCode
                responder.error = error
                responder.delay = delay
                responder.headers = headers
            }
        }

        var lastRequest: URLRequest? {
            Registry.shared.read(host: host)?.lastRequest
        }
    }

    private final class Registry: Sendable {
        static let shared = Registry()

        private let lock = OSAllocatedUnfairLock<[String: Responder]>(initialState: [:])

        func register(host: String) {
            lock.withLock { map in
                map[host] = Responder()
            }
        }

        func unregister(host: String) {
            lock.withLock { map in
                map[host] = nil
            }
        }

        func update(host: String, _ transform: @Sendable (inout Responder) -> Void) {
            lock.withLock { map in
                var responder = map[host] ?? Responder()
                transform(&responder)
                map[host] = responder
            }
        }

        func read(host: String) -> Responder? {
            lock.withLock { map in
                map[host]
            }
        }

        func recordLastRequest(host: String, request: URLRequest) {
            lock.withLock { map in
                guard var responder = map[host] else { return }
                responder.lastRequest = request
                map[host] = responder
            }
        }
    }

    static func register(host: String? = nil) -> Handle {
        let host = host ?? "test-\(UUID().uuidString).invalid"
        Registry.shared.register(host: host)
        return Handle(host: host)
    }

    static func unregister(_ handle: Handle) {
        Registry.shared.unregister(host: handle.host)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return Registry.shared.read(host: host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host,
              let responder = Registry.shared.read(host: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        Registry.shared.recordLastRequest(host: host, request: request)

        if responder.delay > 0 {
            Thread.sleep(forTimeInterval: responder.delay)
        }

        if let error = responder.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responder.statusCode,
            httpVersion: nil,
            headerFields: responder.headers
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = responder.data {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
