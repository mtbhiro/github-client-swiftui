import Foundation
import os

nonisolated final class MockGitHubAuthRepository: GitHubAuthRepositoryProtocol, Sendable {

    private struct MockState: Sendable {
        var deviceCodeResult: Result<GitHubDeviceCode, Error> = .success(.sample)
        var pollHandler: (@Sendable (String) async throws -> GitHubAuthTokenOutcome)?
        var userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample)
        var token: String?
        var saveTokenError: (any Error)?
        var pollCallCount: Int = 0
        var lastPollDeviceCode: String?
        var savedTokenHistory: [String] = []
    }

    private let stateLock = OSAllocatedUnfairLock<MockState>(initialState: MockState())

    init(
        deviceCodeResult: Result<GitHubDeviceCode, Error> = .success(.sample),
        userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample),
        initialToken: String? = nil
    ) {
        stateLock.withLock { state in
            state.deviceCodeResult = deviceCodeResult
            state.userResult = userResult
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

    func setSaveTokenError(_ error: (any Error)?) {
        stateLock.withLock { $0.saveTokenError = error }
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
        try stateLock.withLock { state in
            if let error = state.saveTokenError { throw error }
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
}

nonisolated extension GitHubDeviceCode {
    static let sample = GitHubDeviceCode(
        deviceCode: "sample-device-code",
        userCode: "WDJB-MJHT",
        // swiftlint:disable:next force_unwrapping
        verificationURL: URL(string: "https://github.com/login/device")!,
        expiresIn: 900,
        interval: 5
    )
}

nonisolated extension GitHubAuthenticatedUser {
    static let sample = GitHubAuthenticatedUser(
        login: "octocat",
        name: "The Octocat",
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?v=4")
    )
}
