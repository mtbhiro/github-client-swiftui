import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct SettingsModelTests {

    private func makeStorage() -> UserDefaultsStorage<GitHubAuthenticatedUser> {
        let suiteName = "SettingsModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsStorage(key: "profile", defaults: defaults)
    }

    private struct SUT {
        let model: SettingsModel
        let authState: GitHubAuthState
        let rateLimit: RateLimitObserver
        let service: MockGitHubAuthService
        let profileCache: UserDefaultsStorage<GitHubAuthenticatedUser>
    }

    private func makeSUT(
        initialToken: String? = nil,
        cachedProfile: GitHubAuthenticatedUser? = nil,
        userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample)
    ) -> SUT {
        let cache = makeStorage()
        if let cachedProfile {
            cache.save(cachedProfile)
        }
        let service = MockGitHubAuthService(
            userResult: userResult,
            initialToken: initialToken
        )
        let authState = GitHubAuthState(service: service, profileCache: cache)
        let rateLimit = RateLimitObserver()
        let model = SettingsModel(authState: authState, rateLimit: rateLimit, service: service)
        return SUT(model: model, authState: authState, rateLimit: rateLimit, service: service, profileCache: cache)
    }

    private func waitForInflight(_ model: SettingsModel) async {
        await model.inFlightTask?.value
    }

    // MARK: - profileState

    @Test func signedOut_yieldsHiddenProfile() {
        let sut = makeSUT()
        #expect(sut.model.profileState == .hidden)
    }

    @Test func signedIn_withoutUser_yieldsLoadingProfile() {
        let sut = makeSUT(initialToken: "tok")
        #expect(sut.model.profileState == .loading)
    }

    @Test func signedIn_withFreshUser_yieldsLoadedProfile() {
        let sut = makeSUT(initialToken: "tok")
        sut.authState.completeSignIn(token: "tok", user: .sample)
        if case let .loaded(u) = sut.model.profileState {
            #expect(u == .sample)
        } else {
            Issue.record("Expected .loaded, got \(sut.model.profileState)")
        }
    }

    @Test func signedIn_withCachedUser_yieldsCachedProfile() {
        let sut = makeSUT(initialToken: "tok", cachedProfile: .sample)
        if case let .cached(u) = sut.model.profileState {
            #expect(u == .sample)
        } else {
            Issue.record("Expected .cached, got \(sut.model.profileState)")
        }
    }

    // MARK: - refreshProfile

    @Test func refreshProfile_success_movesFromCachedToLoaded() async {
        let fresh = GitHubAuthenticatedUser(login: "octo2", name: "v2", avatarURL: nil)
        let sut = makeSUT(
            initialToken: "tok",
            cachedProfile: .sample,
            userResult: .success(fresh)
        )
        #expect(sut.model.profileState == .cached(.sample))

        sut.model.refreshProfile()
        await waitForInflight(sut.model)

        #expect(sut.model.profileState == .loaded(fresh))
        #expect(sut.profileCache.load() == fresh)
    }

    @Test func refreshProfile_failure_keepsCachedProfile() async {
        let sut = makeSUT(
            initialToken: "tok",
            cachedProfile: .sample,
            userResult: .failure(URLError(.notConnectedToInternet))
        )
        #expect(sut.model.profileState == .cached(.sample))

        sut.model.refreshProfile()
        await waitForInflight(sut.model)

        #expect(sut.model.profileState == .cached(.sample))
    }

    @Test func refreshProfile_whenSignedOut_doesNothing() async {
        let sut = makeSUT()
        sut.model.refreshProfile()
        await waitForInflight(sut.model)
        #expect(sut.authState.phase == .signedOut)
    }

    // MARK: - logout dialog

    @Test func requestLogout_whenSignedIn_showsConfirmation() {
        let sut = makeSUT(initialToken: "tok")
        sut.model.requestLogout()
        #expect(sut.model.logoutConfirmationVisible == true)
    }

    @Test func confirmLogout_signsOut_andResetsRateLimit() {
        let sut = makeSUT(initialToken: "tok")
        sut.rateLimit.update(from: [
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "4999",
        ])
        sut.model.requestLogout()
        sut.model.confirmLogout()

        #expect(sut.model.logoutConfirmationVisible == false)
        #expect(sut.authState.phase == .signedOut)
        #expect(sut.rateLimit.snapshot == nil)
    }

    @Test func cancelLogout_keepsState() {
        let sut = makeSUT(initialToken: "tok")
        sut.model.requestLogout()
        sut.model.cancelLogout()

        #expect(sut.model.logoutConfirmationVisible == false)
        #expect(sut.authState.phase == .signedIn)
    }

    @Test func requestLogout_whenSignedOut_doesNothing() {
        let sut = makeSUT()
        sut.model.requestLogout()
        #expect(sut.model.logoutConfirmationVisible == false)
    }

    @Test func onAuthPhaseChanged_resetsRateLimit() {
        let sut = makeSUT()
        sut.rateLimit.update(from: [
            "X-RateLimit-Limit": "60",
            "X-RateLimit-Remaining": "30",
        ])
        sut.model.onAuthPhaseChanged()
        #expect(sut.rateLimit.snapshot == nil)
    }
}
