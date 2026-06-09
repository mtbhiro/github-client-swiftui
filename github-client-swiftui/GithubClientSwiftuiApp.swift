import SwiftUI

@main
struct GithubClientSwiftuiApp: App {
    @State private var bookmarkStore = BookmarkStore()
    @State private var coordinator = AppCoordinator()
    @State private var authStack: AuthStack

    init() {
        let stack = AuthStack.makeProduction()
        _authStack = State(initialValue: stack)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bookmarkStore)
                .environment(coordinator)
                .environment(authStack.authState)
                .environment(authStack.rateLimit)
                .environment(authStack.authFactory)
                .environment(\.githubRepository, authStack.repository)
        }
    }
}

/// 起動時に 1 回だけ作る Auth 関連オブジェクトの束。
@MainActor
struct AuthStack {
    let authState: GitHubAuthState
    let rateLimit: RateLimitObserver
    let authFactory: AuthFactory
    let repository: any GithubRepoRepositoryProtocol

    static func makeProduction() -> AuthStack {
        let service = GitHubAuthService()
        let authState = GitHubAuthState(service: service)
        let rateLimit = RateLimitObserver()
        let factory = AuthFactory(service: service)
        let httpClient = AuthenticatedHttpClient(
            upstream: URLSessionHttpClient(session: URLSessionHttpClient.makeDefaultSession()),
            authState: authState,
            rateLimit: rateLimit
        )
        let repository = GithubRepoRepository(httpClient: httpClient)

        return AuthStack(
            authState: authState,
            rateLimit: rateLimit,
            authFactory: factory,
            repository: repository
        )
    }
}
