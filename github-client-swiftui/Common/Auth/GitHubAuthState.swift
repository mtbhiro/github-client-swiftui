import Foundation
import Observation
import os

enum GitHubAuthPhase: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn
}

@Observable
final class GitHubAuthState {

    enum ProfilePhase: Sendable, Equatable {
        case hidden
        case loading
        case loaded(GitHubAuthenticatedUser)
        case cached(GitHubAuthenticatedUser)
    }

    private(set) var phase: GitHubAuthPhase
    private(set) var token: String?
    private(set) var user: GitHubAuthenticatedUser?
    private(set) var userIsFromCache: Bool = false

    var inFlightTask: Task<Void, Never>? { profileTask }
    private var profileTask: Task<Void, Never>?

    private let repository: GitHubAuthRepositoryProtocol
    private let profileCache: UserDefaultsStorage<GitHubAuthenticatedUser>?

    init(
        repository: GitHubAuthRepositoryProtocol,
        profileCache: UserDefaultsStorage<GitHubAuthenticatedUser>? = UserDefaultsStorage(
            key: "github.auth.profileCache"
        )
    ) {
        self.repository = repository
        self.profileCache = profileCache
        if let stored = repository.loadToken() {
            self.token = stored
            self.phase = .signedIn
            if let cached = profileCache?.load() {
                self.user = cached
                self.userIsFromCache = true
            }
            refreshProfile()
        } else {
            self.phase = .signedOut
        }
    }

    var profilePhase: ProfilePhase {
        switch phase {
        case .signedOut, .signingIn:
            return .hidden
        case .signedIn:
            if let user {
                return userIsFromCache ? .cached(user) : .loaded(user)
            }
            return .loading
        }
    }

    private func refreshProfile() {
        guard phase == .signedIn, let token else { return }

        profileTask?.cancel()
        profileTask = Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.repository.fetchAuthenticatedUser(token: token)
                guard !Task.isCancelled else { return }
                if self.phase == .signedIn {
                    self.updateProfile(user)
                }
            } catch is CancellationError {
            } catch {
            }
        }
    }

    func beginSigningIn() {
        Logger.auth.info("Auth phase: \(String(describing: self.phase)) → signingIn")
        phase = .signingIn
    }

    func cancelSigningIn() {
        guard phase == .signingIn else { return }
        phase = .signedOut
    }

    @discardableResult
    func completeSignIn(token: String, user: GitHubAuthenticatedUser) -> Bool {
        do {
            try repository.saveToken(token)
        } catch {
            return false
        }
        self.token = token
        self.user = user
        self.userIsFromCache = false
        profileCache?.save(user)
        phase = .signedIn
        Logger.auth.info("Auth phase: → signedIn (token saved)")
        return true
    }

    func updateProfile(_ user: GitHubAuthenticatedUser) {
        guard phase == .signedIn else { return }
        self.user = user
        self.userIsFromCache = false
        profileCache?.save(user)
    }

    func handle401() {
        guard phase != .signedOut else { return }
        Logger.auth.error("Received 401 — clearing session")
        clearSession()
    }

    func logout() {
        Logger.auth.info("User-initiated logout")
        clearSession()
    }

    private func clearSession() {
        try? repository.clearToken()
        token = nil
        user = nil
        userIsFromCache = false
        profileCache?.delete()
        phase = .signedOut
    }
}
