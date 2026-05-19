import Foundation
import Observation

enum GitHubAuthPhase: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn
}

@Observable
final class GitHubAuthState {
    private(set) var phase: GitHubAuthPhase
    private(set) var token: String?
    private(set) var user: GitHubAuthenticatedUser?
    private(set) var userIsFromCache: Bool = false

    private let service: GitHubAuthServiceProtocol
    private let profileCache: UserDefaultsStorage<GitHubAuthenticatedUser>?

    init(
        service: GitHubAuthServiceProtocol,
        profileCache: UserDefaultsStorage<GitHubAuthenticatedUser>? = UserDefaultsStorage(
            key: "github.auth.profileCache"
        )
    ) {
        self.service = service
        self.profileCache = profileCache
        if let stored = service.loadToken() {
            self.token = stored
            self.phase = .signedIn
            if let cached = profileCache?.load() {
                self.user = cached
                self.userIsFromCache = true
            }
        } else {
            self.phase = .signedOut
        }
    }

    func beginSigningIn() {
        phase = .signingIn
    }

    func cancelSigningIn() {
        guard phase == .signingIn else { return }
        phase = .signedOut
    }

    func completeSignIn(token: String, user: GitHubAuthenticatedUser) {
        do {
            try service.saveToken(token)
        } catch {
            return
        }
        self.token = token
        self.user = user
        self.userIsFromCache = false
        profileCache?.save(user)
        phase = .signedIn
    }

    func updateProfile(_ user: GitHubAuthenticatedUser) {
        guard phase == .signedIn else { return }
        self.user = user
        self.userIsFromCache = false
        profileCache?.save(user)
    }

    func handle401() {
        guard phase != .signedOut else { return }
        try? service.clearToken()
        token = nil
        user = nil
        userIsFromCache = false
        profileCache?.delete()
        phase = .signedOut
    }

    func logout() {
        try? service.clearToken()
        token = nil
        user = nil
        userIsFromCache = false
        profileCache?.delete()
        phase = .signedOut
    }
}
