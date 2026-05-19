import Foundation
import os

/// テスト / Preview 用の GitHubAuthService の Mock。Keychain と handler を含む状態はロックで守るため
/// `nonisolated final class` のまま `Sendable` を満たせる。
nonisolated final class MockGitHubAuthService: GitHubAuthServiceProtocol, Sendable {

    private struct MockState: Sendable {
        var deviceCodeResult: Result<GitHubDeviceCode, Error> = .success(.sample)
        var pollHandler: (@Sendable (String) async throws -> GitHubAuthTokenOutcome)?
        var userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample)
        var clientIDValue: String? = "mock-client-id"
        var token: String?
        var pollCallCount: Int = 0
        var lastPollDeviceCode: String?
        var savedTokenHistory: [String] = []
    }

    private let stateLock = OSAllocatedUnfairLock<MockState>(initialState: MockState())

    init(
        deviceCodeResult: Result<GitHubDeviceCode, Error> = .success(.sample),
        userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample),
        clientIDValue: String? = "mock-client-id",
        initialToken: String? = nil
    ) {
        stateLock.withLock { state in
            state.deviceCodeResult = deviceCodeResult
            state.userResult = userResult
            state.clientIDValue = clientIDValue
            state.token = initialToken
        }
    }

    // MARK: - Observation properties (test side)

    var pollCallCount: Int { stateLock.withLock { $0.pollCallCount } }
    var lastPollDeviceCode: String? { stateLock.withLock { $0.lastPollDeviceCode } }
    var savedTokenHistory: [String] { stateLock.withLock { $0.savedTokenHistory } }

    // MARK: - Test mutators

    func setDeviceCodeResult(_ result: Result<GitHubDeviceCode, Error>) {
        stateLock.withLock { $0.deviceCodeResult = result }
    }

    func setPollHandler(_ handler: (@Sendable (String) async throws -> GitHubAuthTokenOutcome)?) {
        stateLock.withLock { $0.pollHandler = handler }
    }

    func setUserResult(_ result: Result<GitHubAuthenticatedUser, Error>) {
        stateLock.withLock { $0.userResult = result }
    }

    func setClientID(_ value: String?) {
        stateLock.withLock { $0.clientIDValue = value }
    }

    // MARK: - Protocol

    func requestDeviceCode() async throws -> GitHubDeviceCode {
        let result = stateLock.withLock { $0.deviceCodeResult }
        return try result.get()
    }

    func pollAccessToken(deviceCode: String) async throws -> GitHubAuthTokenOutcome {
        let handler = stateLock.withLock { state -> (@Sendable (String) async throws -> GitHubAuthTokenOutcome)? in
            state.pollCallCount += 1
            state.lastPollDeviceCode = deviceCode
            return state.pollHandler
        }
        if let handler {
            return try await handler(deviceCode)
        }
        return .pending
    }

    func fetchAuthenticatedUser(token: String) async throws -> GitHubAuthenticatedUser {
        let result = stateLock.withLock { $0.userResult }
        return try result.get()
    }

    func saveToken(_ token: String) throws {
        stateLock.withLock { state in
            state.token = token
            state.savedTokenHistory.append(token)
        }
    }

    func loadToken() -> String? {
        stateLock.withLock { $0.token }
    }

    func clearToken() throws {
        stateLock.withLock { $0.token = nil }
    }

    func clientID() throws -> String {
        let value = stateLock.withLock { $0.clientIDValue }
        guard let value, !value.isEmpty else {
            throw GitHubAuthConfigError.missingClientID
        }
        return value
    }
}

extension GitHubDeviceCode {
    nonisolated static let sample = GitHubDeviceCode(
        deviceCode: "sample-device-code",
        userCode: "WDJB-MJHT",
        verificationURL: URL(string: "https://github.com/login/device")!,
        expiresIn: 900,
        interval: 5
    )
}

extension GitHubAuthenticatedUser {
    nonisolated static let sample = GitHubAuthenticatedUser(
        login: "octocat",
        name: "The Octocat",
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4")
    )
}
