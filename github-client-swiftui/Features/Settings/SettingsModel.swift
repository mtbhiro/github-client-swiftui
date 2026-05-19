import Foundation
import Observation

enum SettingsProfileState: Equatable, Sendable {
    case hidden
    case loading
    case loaded(GitHubAuthenticatedUser)
    case cached(GitHubAuthenticatedUser)
}

@Observable
final class SettingsModel {
    private(set) var logoutConfirmationVisible: Bool = false

    var inFlightTask: Task<Void, Never>? { profileTask }
    private var profileTask: Task<Void, Never>?

    let authState: GitHubAuthState
    let rateLimit: RateLimitObserver
    private let service: GitHubAuthServiceProtocol

    init(authState: GitHubAuthState, rateLimit: RateLimitObserver, service: GitHubAuthServiceProtocol) {
        self.authState = authState
        self.rateLimit = rateLimit
        self.service = service
    }

    var profileState: SettingsProfileState {
        switch authState.phase {
        case .signedOut, .signingIn:
            return .hidden
        case .signedIn:
            if let user = authState.user {
                return authState.userIsFromCache ? .cached(user) : .loaded(user)
            }
            return .loading
        }
    }

    /// 起動直後 (および sign-in 完了直後) に発火し、`GET /user` でプロフィールを最新化する。
    /// 失敗時の挙動は 2 通り:
    ///   - 401 → AuthenticatedHttpClient 側で signedOut に倒される (PRD AC-6.3)。本 Model は別の動作をしない。
    ///   - その他 (network / 5xx) → 既存プロフィール (cache or nil) を維持する (PRD AC-5.2)。
    func refreshProfile() {
        guard authState.phase == .signedIn, let token = authState.token else { return }

        profileTask?.cancel()
        profileTask = Task { [weak self] in
            guard let self else { return }
            do {
                let user = try await self.service.fetchAuthenticatedUser(token: token)
                guard !Task.isCancelled else { return }
                if self.authState.phase == .signedIn {
                    self.authState.updateProfile(user)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func requestLogout() {
        guard authState.phase == .signedIn else { return }
        logoutConfirmationVisible = true
    }

    func confirmLogout() {
        logoutConfirmationVisible = false
        authState.logout()
        rateLimit.reset()
    }

    func cancelLogout() {
        logoutConfirmationVisible = false
    }

    /// sign-in 状態の変化 (signedOut → signedIn または逆) を契機にレート制限をリセットする (PRD AC-3.4)。
    /// View 側から `.onChange(of: authState.phase)` で呼ぶ前提。
    func onAuthPhaseChanged() {
        rateLimit.reset()
    }
}
