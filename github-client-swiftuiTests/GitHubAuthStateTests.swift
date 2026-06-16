import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct GitHubAuthStateTests {

    private func makeStorage() -> UserDefaultsStorage<GitHubAuthenticatedUser> {
        let suiteName = "GitHubAuthStateTests.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsStorage(key: "profile", defaults: defaults)
    }

    private func makeState(
        initialToken: String? = nil,
        cachedProfile: GitHubAuthenticatedUser? = nil,
        userResult: Result<GitHubAuthenticatedUser, Error> = .success(.sample)
    ) -> (state: GitHubAuthState, service: MockGitHubAuthService, cache: UserDefaultsStorage<GitHubAuthenticatedUser>) {
        let cache = makeStorage()
        if let cachedProfile {
            cache.save(cachedProfile)
        }
        let service = MockGitHubAuthService(
            userResult: userResult,
            initialToken: initialToken
        )
        let state = GitHubAuthState(service: service, profileCache: cache)
        return (state, service, cache)
    }

    // MARK: - init

    @Test func init_withNoStoredToken_isSignedOut() {
        let service = MockGitHubAuthService()
        let state = GitHubAuthState(service: service, profileCache: makeStorage())

        #expect(state.phase == .signedOut)
        #expect(state.token == nil)
        #expect(state.user == nil)
    }

    @Test func init_withStoredToken_restoresSignedIn() {
        let service = MockGitHubAuthService(initialToken: "stored-token")
        let state = GitHubAuthState(service: service, profileCache: makeStorage())

        #expect(state.phase == .signedIn)
        #expect(state.token == "stored-token")
    }

    @Test func init_withStoredToken_andCachedProfile_loadsCachedProfile() {
        let service = MockGitHubAuthService(initialToken: "tok")
        let cache = makeStorage()
        cache.save(.sample)

        let state = GitHubAuthState(service: service, profileCache: cache)

        #expect(state.user == .sample)
        #expect(state.userIsFromCache == true)
    }

    // MARK: - completeSignIn

    @Test func completeSignIn_savesTokenAndUpdatesState() {
        let service = MockGitHubAuthService()
        let cache = makeStorage()
        let state = GitHubAuthState(service: service, profileCache: cache)

        let result = state.completeSignIn(token: "new-token", user: .sample)

        #expect(result == true)
        #expect(state.phase == .signedIn)
        #expect(state.token == "new-token")
        #expect(state.user == .sample)
        #expect(state.userIsFromCache == false)
        #expect(service.loadToken() == "new-token")
        #expect(cache.load() == .sample)
    }

    @Test func completeSignIn_whenTokenSaveFails_returnsFalseAndKeepsSignedOut() {
        let service = MockGitHubAuthService()
        service.setSaveTokenError(KeychainStorageError.osStatus(-25300))
        let cache = makeStorage()
        let state = GitHubAuthState(service: service, profileCache: cache)

        let result = state.completeSignIn(token: "tok", user: .sample)

        #expect(result == false)
        #expect(state.phase == .signedOut)
        #expect(state.token == nil)
        #expect(state.user == nil)
    }

    // MARK: - logout / handle401

    @Test func logout_clearsStateAndCache() {
        let service = MockGitHubAuthService(initialToken: "tok")
        let cache = makeStorage()
        cache.save(.sample)
        let state = GitHubAuthState(service: service, profileCache: cache)

        state.logout()

        #expect(state.phase == .signedOut)
        #expect(state.token == nil)
        #expect(state.user == nil)
        #expect(service.loadToken() == nil)
        #expect(cache.load() == nil)
    }

    @Test func handle401_whenSignedIn_clearsStateAndCache() {
        let service = MockGitHubAuthService(initialToken: "tok")
        let cache = makeStorage()
        cache.save(.sample)
        let state = GitHubAuthState(service: service, profileCache: cache)

        state.handle401()

        #expect(state.phase == .signedOut)
        #expect(state.token == nil)
        #expect(state.user == nil)
        #expect(service.loadToken() == nil)
        #expect(cache.load() == nil)
    }

    @Test func handle401_whenSignedOut_doesNothing() {
        let service = MockGitHubAuthService()
        let state = GitHubAuthState(service: service, profileCache: makeStorage())

        state.handle401()
        #expect(state.phase == .signedOut)
    }

    // MARK: - beginSigningIn / cancelSigningIn

    @Test func beginSigningIn_setsSigningInPhase_andCancelReverts() {
        let service = MockGitHubAuthService()
        let state = GitHubAuthState(service: service, profileCache: makeStorage())

        state.beginSigningIn()
        #expect(state.phase == .signingIn)

        state.cancelSigningIn()
        #expect(state.phase == .signedOut)
    }

    // MARK: - updateProfile

    @Test func updateProfile_onlyAppliesWhenSignedIn_clearsCachedFlag() {
        let service = MockGitHubAuthService(initialToken: "tok")
        let cache = makeStorage()
        cache.save(.sample)
        let state = GitHubAuthState(service: service, profileCache: cache)
        #expect(state.userIsFromCache == true)

        let fresh = GitHubAuthenticatedUser(login: "x", name: "X", avatarURL: nil)
        state.updateProfile(fresh)

        #expect(state.user == fresh)
        #expect(state.userIsFromCache == false)
        #expect(cache.load() == fresh)
    }

    // MARK: - profilePhase

    @Test func signedOut_yieldsHiddenProfile() {
        let (state, _, _) = makeState()
        #expect(state.profilePhase == .hidden)
    }

    @Test func signedIn_withoutUser_yieldsLoadingProfile() {
        let (state, _, _) = makeState(initialToken: "tok")
        #expect(state.profilePhase == .loading)
    }

    @Test func signedIn_withFreshUser_yieldsLoadedProfile() {
        let (state, _, _) = makeState(initialToken: "tok")
        state.completeSignIn(token: "tok", user: .sample)
        if case let .loaded(u) = state.profilePhase {
            #expect(u == .sample)
        } else {
            Issue.record("Expected .loaded, got \(state.profilePhase)")
        }
    }

    @Test func signedIn_withCachedUser_yieldsCachedProfile() {
        let (state, _, _) = makeState(initialToken: "tok", cachedProfile: .sample)
        if case let .cached(u) = state.profilePhase {
            #expect(u == .sample)
        } else {
            Issue.record("Expected .cached, got \(state.profilePhase)")
        }
    }

    // MARK: - refreshProfile (init 時に自動発火)

    @Test func init_withToken_autoRefreshesProfile_success() async {
        let fresh = GitHubAuthenticatedUser(login: "octo2", name: "v2", avatarURL: nil)
        let (state, _, cache) = makeState(
            initialToken: "tok",
            cachedProfile: .sample,
            userResult: .success(fresh)
        )

        await state.inFlightTask?.value

        #expect(state.profilePhase == .loaded(fresh))
        #expect(cache.load() == fresh)
    }

    @Test func init_withToken_autoRefreshesProfile_failure_keepsCached() async {
        let (state, _, _) = makeState(
            initialToken: "tok",
            cachedProfile: .sample,
            userResult: .failure(URLError(.notConnectedToInternet))
        )

        await state.inFlightTask?.value

        #expect(state.profilePhase == .cached(.sample))
    }

    @Test func init_withoutToken_doesNotRefresh() async {
        let (state, _, _) = makeState()
        #expect(state.inFlightTask == nil)
        #expect(state.phase == .signedOut)
    }
}

@MainActor
struct RateLimitObserverTests {

    @Test func update_withValidHeaders_setsSnapshot() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "x-ratelimit-limit": "5000",
            "x-ratelimit-remaining": "4999",
        ])
        #expect(observer.snapshot == RateLimitSnapshot(limit: 5000, remaining: 4999))
    }

    @Test func update_missingHeaders_doesNotOverwrite() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "59",
        ])
        observer.update(from: [:])
        #expect(observer.snapshot == RateLimitSnapshot(limit: 60, remaining: 59))
    }

    @Test func reset_clearsSnapshot() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "10",
        ])
        observer.reset()
        #expect(observer.snapshot == nil)
    }
}
