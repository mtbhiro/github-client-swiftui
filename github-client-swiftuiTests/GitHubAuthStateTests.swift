import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct GitHubAuthStateTests {

    private func makeStorage() -> UserDefaultsStorage<GitHubAuthenticatedUser> {
        let suiteName = "GitHubAuthStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsStorage(key: "profile", defaults: defaults)
    }

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

    @Test func completeSignIn_savesTokenAndUpdatesState() {
        let service = MockGitHubAuthService()
        let cache = makeStorage()
        let state = GitHubAuthState(service: service, profileCache: cache)

        state.completeSignIn(token: "new-token", user: .sample)

        #expect(state.phase == .signedIn)
        #expect(state.token == "new-token")
        #expect(state.user == .sample)
        #expect(state.userIsFromCache == false)
        #expect(service.loadToken() == "new-token")
        #expect(cache.load() == .sample)
    }

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

    @Test func beginSigningIn_setsSigningInPhase_andCancelReverts() {
        let service = MockGitHubAuthService()
        let state = GitHubAuthState(service: service, profileCache: makeStorage())

        state.beginSigningIn()
        #expect(state.phase == .signingIn)

        state.cancelSigningIn()
        #expect(state.phase == .signedOut)
    }

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
}

@MainActor
struct RateLimitObserverTests {

    @Test func update_withValidHeaders_setsSnapshot() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "4999",
        ])
        #expect(observer.snapshot == RateLimitSnapshot(limit: 5000, remaining: 4999))
    }

    @Test func update_withLowercaseHeaders_setsSnapshot() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "59",
        ])
        #expect(observer.snapshot == RateLimitSnapshot(limit: 60, remaining: 59))
    }

    @Test func update_missingHeaders_doesNotOverwrite() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "X-RateLimit-Limit": "60",
            "X-RateLimit-Remaining": "59",
        ])
        observer.update(from: [:])
        #expect(observer.snapshot == RateLimitSnapshot(limit: 60, remaining: 59))
    }

    @Test func reset_clearsSnapshot() {
        let observer = RateLimitObserver()
        observer.update(from: [
            "X-RateLimit-Limit": "60",
            "X-RateLimit-Remaining": "10",
        ])
        observer.reset()
        #expect(observer.snapshot == nil)
    }
}
