import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct AuthenticatedHttpClientTests {

    private struct SampleResponse: Decodable, Sendable, Equatable {
        let id: Int
    }

    private struct SUT {
        let client: AuthenticatedHttpClient
        let stub: StubURLProtocol.Handle
        let authState: GitHubAuthState
        let rateLimit: RateLimitObserver
        let mockService: MockGitHubAuthService
    }

    private func makeStorage() -> UserDefaultsStorage<GitHubAuthenticatedUser> {
        let suiteName = "AuthenticatedHttpClientTests.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsStorage(key: "profile", defaults: defaults)
    }

    private func makeSUT(initialToken: String? = nil) -> SUT {
        // `AuthenticatedHttpClient.shouldAttachBearer` が suffix `.github.com` を見るので、
        // stub ホストを `test-{UUID}.api.github.com` 形式に揃える。
        // テストごとに固有のため並列実行下でも衝突しない。
        let host = "test-\(UUID().uuidString).api.github.com"
        let stub = StubURLProtocol.register(host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let upstream = URLSessionHttpClient(session: session)
        let mockService = MockGitHubAuthService(initialToken: initialToken)
        let authState = GitHubAuthState(service: mockService, profileCache: makeStorage())
        let rateLimit = RateLimitObserver()
        let client = AuthenticatedHttpClient(upstream: upstream, authState: authState, rateLimit: rateLimit)
        return SUT(client: client, stub: stub, authState: authState, rateLimit: rateLimit, mockService: mockService)
    }

    /// `*.github.com` 判定の対象外にしたいテスト用に、無関係なホストで stub を払い出す。
    private func makeNonGitHubStub() -> StubURLProtocol.Handle {
        StubURLProtocol.register(host: "test-\(UUID().uuidString).invalid")
    }

    // MARK: - Bearer 注入

    @Test func signedIn_attachesBearerToken_andGitHubHeaders() async throws {
        let sut = makeSUT()
        sut.authState.completeSignIn(token: "gho_xxx", user: .sample)
        // swiftlint:disable:next force_unwrapping
        let body = #"{"id":1}"#.data(using: .utf8)!
        sut.stub.respond(data: body, statusCode: 200)
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        let _: SampleResponse = try await sut.client.send(request)

        #expect(sut.stub.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_xxx")
        #expect(sut.stub.lastRequest?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func signedOut_doesNotAttachBearer() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let body = #"{"id":1}"#.data(using: .utf8)!
        sut.stub.respond(data: body, statusCode: 200)
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        let _: SampleResponse = try await sut.client.send(request)

        #expect(sut.stub.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func customNonGitHubHost_doesNotAttachBearer() async throws {
        let sut = makeSUT()
        sut.authState.completeSignIn(token: "gho_xxx", user: .sample)
        let nonGitHub = makeNonGitHubStub()
        // swiftlint:disable:next force_unwrapping
        let body = #"{"id":1}"#.data(using: .utf8)!
        nonGitHub.respond(data: body, statusCode: 200)

        let request = HttpRequest(host: nonGitHub.apiHost, path: "/echo")
        let _: SampleResponse = try await sut.client.send(request)

        #expect(nonGitHub.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // MARK: - 401 ハンドリング

    @Test func unauthorizedFromGitHubAPI_triggers401Handler_andSignsOut() async {
        let sut = makeSUT(initialToken: "tok")
        #expect(sut.authState.phase == .signedIn)
        sut.stub.respond(data: Data(), statusCode: 401)
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        await #expect {
            let _: SampleResponse = try await sut.client.send(request)
        } throws: { error in
            guard case let HttpClientError.httpError(code, _, _) = error else { return false }
            return code == 401
        }

        #expect(sut.authState.phase == .signedOut)
    }

    @Test func rateLimited403_doesNotSignOut() async {
        let sut = makeSUT(initialToken: "tok")
        sut.stub.respond(data: Data(), statusCode: 403, headers: [
            "X-RateLimit-Remaining": "0",
        ])
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        await #expect {
            let _: SampleResponse = try await sut.client.send(request)
        } throws: { error in
            guard case let HttpClientError.httpError(code, _, _) = error else { return false }
            return code == 403
        }

        #expect(sut.authState.phase == .signedIn)
    }

    @Test func serverError500_doesNotSignOut() async {
        let sut = makeSUT(initialToken: "tok")
        sut.stub.respond(data: Data(), statusCode: 500)
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        await #expect {
            let _: SampleResponse = try await sut.client.send(request)
        } throws: { _ in true }

        #expect(sut.authState.phase == .signedIn)
    }

    // MARK: - レート制限ヘッダ観測

    @Test func successResponse_updatesRateLimitObserver() async throws {
        let sut = makeSUT(initialToken: "tok")
        // swiftlint:disable:next force_unwrapping
        let body = #"{"id":1}"#.data(using: .utf8)!
        sut.stub.respond(data: body, statusCode: 200, headers: [
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "4999",
        ])
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        let _: SampleResponse = try await sut.client.send(request)

        #expect(sut.rateLimit.snapshot == RateLimitSnapshot(limit: 5000, remaining: 4999))
    }

    @Test func failureResponse_alsoUpdatesRateLimit() async {
        let sut = makeSUT(initialToken: "tok")
        sut.stub.respond(data: Data(), statusCode: 403, headers: [
            "X-RateLimit-Limit": "60",
            "X-RateLimit-Remaining": "0",
        ])
        let request = HttpRequest(host: sut.stub.apiHost, path: "/user")

        await #expect {
            let _: SampleResponse = try await sut.client.send(request)
        } throws: { _ in true }

        #expect(sut.rateLimit.snapshot == RateLimitSnapshot(limit: 60, remaining: 0))
    }

    @Test func nonGitHubHost_doesNotUpdateRateLimit() async throws {
        let sut = makeSUT()
        let nonGitHub = makeNonGitHubStub()
        // swiftlint:disable:next force_unwrapping
        let body = #"{"id":1}"#.data(using: .utf8)!
        nonGitHub.respond(data: body, statusCode: 200, headers: [
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "4999",
        ])
        let request = HttpRequest(host: nonGitHub.apiHost, path: "/echo")
        let _: SampleResponse = try await sut.client.send(request)

        #expect(sut.rateLimit.snapshot == nil)
    }
}
