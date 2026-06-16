import Foundation
import Testing
@testable import github_client_swiftui

struct GitHubAuthRepositoryTests {

    private struct SUT {
        let repository: GitHubAuthRepository
        let oauth: StubURLProtocol.Handle
        let api: StubURLProtocol.Handle
    }

    private func makeSUT(clientID: String? = "test-client-id") -> SUT {
        let oauth = StubURLProtocol.register()
        let api = StubURLProtocol.register()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let httpClient = URLSessionHttpClient(session: session)
        let hosts = GitHubAuthHosts(oauth: oauth.apiHost, api: api.apiHost)
        let repository = GitHubAuthRepository(
            httpClient: httpClient,
            hosts: hosts,
            clientIDProvider: { clientID }
        )
        return SUT(repository: repository, oauth: oauth, api: api)
    }

    // MARK: - requestDeviceCode

    @Test func requestDeviceCode_success_returnsDomain() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"""
        {
            "device_code": "abc",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://github.com/login/device",
            "expires_in": 900,
            "interval": 5
        }
        """#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let code = try await sut.repository.requestDeviceCode()
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.deviceCode == "abc")
        #expect(code.interval == 5)
    }

    @Test func requestDeviceCode_emptyClientID_throwsConfigError() async {
        let sut = makeSUT(clientID: "")
        await #expect(throws: GitHubAuthConfigError.missingClientID) {
            _ = try await sut.repository.requestDeviceCode()
        }
    }

    @Test func requestDeviceCode_includesClientIDAndScope_inQuery() async throws {
        let sut = makeSUT(clientID: "ci-xyz")
        // swiftlint:disable:next force_unwrapping
        let json = #"{"device_code":"x","user_code":"X","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        _ = try await sut.repository.requestDeviceCode()

        let url = try #require(sut.oauth.lastRequest?.url)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "client_id", value: "ci-xyz")))
        #expect(items.contains(URLQueryItem(name: "scope", value: "read:user")))
        #expect(url.path == "/login/device/code")
        #expect(sut.oauth.lastRequest?.httpMethod == "POST")
        #expect(sut.oauth.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    // MARK: - pollAccessToken

    @Test func pollAccessToken_success_returnsToken() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"{"access_token":"gho_xxx","token_type":"bearer","scope":"read:user"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let outcome = try await sut.repository.pollAccessToken(deviceCode: "dc")
        if case let .success(token) = outcome {
            #expect(token == "gho_xxx")
        } else {
            Issue.record("Expected success, got \(outcome)")
        }
    }

    @Test func pollAccessToken_authorizationPending_returnsPending() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"{"error":"authorization_pending"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let outcome = try await sut.repository.pollAccessToken(deviceCode: "dc")
        if case .pending = outcome { } else {
            Issue.record("Expected pending")
        }
    }

    @Test func pollAccessToken_slowDown_returnsSlowDown() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"{"error":"slow_down"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let outcome = try await sut.repository.pollAccessToken(deviceCode: "dc")
        if case .slowDown = outcome { } else {
            Issue.record("Expected slowDown")
        }
    }

    @Test func pollAccessToken_accessDenied_returnsAccessDenied() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"{"error":"access_denied"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let outcome = try await sut.repository.pollAccessToken(deviceCode: "dc")
        if case .accessDenied = outcome { } else {
            Issue.record("Expected accessDenied")
        }
    }

    @Test func pollAccessToken_expiredToken_returnsExpired() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"{"error":"expired_token"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        let outcome = try await sut.repository.pollAccessToken(deviceCode: "dc")
        if case .expiredToken = outcome { } else {
            Issue.record("Expected expiredToken")
        }
    }

    @Test func pollAccessToken_includesDeviceCode_andGrantType() async throws {
        let sut = makeSUT(clientID: "ci")
        // swiftlint:disable:next force_unwrapping
        let json = #"{"error":"authorization_pending"}"#.data(using: .utf8)!
        sut.oauth.respond(data: json, statusCode: 200)

        _ = try await sut.repository.pollAccessToken(deviceCode: "dev-code-123")

        let url = try #require(sut.oauth.lastRequest?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "device_code", value: "dev-code-123")))
        #expect(items.contains(URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code")))
        #expect(url.path == "/login/oauth/access_token")
    }

    // MARK: - fetchAuthenticatedUser

    @Test func fetchAuthenticatedUser_success_returnsUser() async throws {
        let sut = makeSUT()
        // swiftlint:disable:next force_unwrapping
        let json = #"""
        {
            "login": "octo",
            "id": 1,
            "avatar_url": "https://example.com/a.png",
            "name": "Octo"
        }
        """#.data(using: .utf8)!
        sut.api.respond(data: json, statusCode: 200)

        let user = try await sut.repository.fetchAuthenticatedUser(token: "gho_xxx")
        #expect(user.login == "octo")
        #expect(user.name == "Octo")

        #expect(sut.api.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_xxx")
        #expect(sut.api.lastRequest?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }
}
