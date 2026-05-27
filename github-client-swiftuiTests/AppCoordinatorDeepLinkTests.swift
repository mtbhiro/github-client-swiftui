import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct AppCoordinatorDeepLinkTests {

    // MARK: - Helpers

    private func makeCoordinatorWithDirtyState() -> AppCoordinator {
        let c = AppCoordinator()
        // 受信前の "任意の状態" を再現: 検索以外のタブを開いており、全 path に push がある。
        c.selectedTab = .bookmarks
        c.searchPath = [
            .repositoryDetail(GitHubRepoFullName(ownerLogin: "before", name: "search"))
        ]
        c.bookmarksPath = [
            .repositoryDetail(GitHubRepoFullName(ownerLogin: "before", name: "bookmarks"))
        ]
        c.settingsPath = []
        return c
    }

    private let appleSwift = GitHubRepoFullName(ownerLogin: "apple", name: "swift")

    // MARK: - AC-1.2: リポジトリ詳細 deeplink を受信したときに selectedTab と searchPath だけが置換される

    @Test func handle_repoDetailDeepLink_switchesTabToSearchAndReplacesSearchPath() {
        let c = makeCoordinatorWithDirtyState()
        let bookmarksSnapshot = c.bookmarksPath
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift")!)

        #expect(c.selectedTab == .search)
        #expect(c.searchPath == [.repositoryDetail(appleSwift)])
        #expect(c.bookmarksPath == bookmarksSnapshot)
        #expect(c.settingsPath == [])
    }

    // MARK: - AC-2.2: Issue 一覧 deeplink を受信したときに searchPath が 2 要素配列になる

    @Test func handle_repoIssuesDeepLink_replacesSearchPathWithDetailThenIssueList() {
        let c = makeCoordinatorWithDirtyState()
        let bookmarksSnapshot = c.bookmarksPath
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift/issues")!)

        #expect(c.selectedTab == .search)
        #expect(c.searchPath == [
            .repositoryDetail(appleSwift),
            .issueList(appleSwift)
        ])
        #expect(c.bookmarksPath == bookmarksSnapshot)
        #expect(c.settingsPath == [])
    }

    // MARK: - AC-3.1: 受信前のスタック内容に依存せず、searchPath は常に置換される

    @Test func handle_replacesExistingSearchPathRegardlessOfPriorPushes() {
        let c = AppCoordinator()
        let other = GitHubRepoFullName(ownerLogin: "other", name: "repo")
        c.selectedTab = .search
        c.searchPath = [
            .repositoryDetail(other),
            .issueList(other),
            .issueDetail(other, number: 42)
        ]
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift")!)

        #expect(c.searchPath == [.repositoryDetail(appleSwift)])
    }

    // MARK: - AC-4.1: 不正 URL ではナビゲーション状態を変更しない

    @Test(arguments: [
        "githubclient://repo",
        "githubclient://repo/",
        "githubclient://repo/apple",
        "githubclient://repo/apple/swift/",
        "githubclient://repo/apple/swift/issues/",
        "githubclient://repo//swift",
        "githubclient://repo/apple//issues",
        "githubclient://repo/apple/swift/pulls",
        "githubclient://repo/apple/swift/issues/1",
        "githubclient://repo/apple/swift?ref=main",
        "githubclient://repo/apple/swift#readme",
        "githubclient://user/apple",
    ])
    func handle_invalidUrl_doesNotMutateAnyPathOrTab(_ urlString: String) {
        let c = makeCoordinatorWithDirtyState()
        let tabBefore = c.selectedTab
        let searchBefore = c.searchPath
        let bookmarksBefore = c.bookmarksPath
        let settingsBefore = c.settingsPath
        // swiftlint:disable:next force_unwrapping
        c.handle(deepLink: URL(string: urlString)!)
        #expect(c.selectedTab == tabBefore)
        #expect(c.searchPath == searchBefore)
        #expect(c.bookmarksPath == bookmarksBefore)
        #expect(c.settingsPath == settingsBefore)
    }

    // MARK: - AC-4.2: 非対象スキームでは何もしない

    @Test func handle_nonGithubclientScheme_doesNotMutateAnyState() {
        let c = makeCoordinatorWithDirtyState()
        let tabBefore = c.selectedTab
        let searchBefore = c.searchPath
        let bookmarksBefore = c.bookmarksPath
        let settingsBefore = c.settingsPath
        c.handle(deepLink: URL(string: "https://github.com/apple/swift")!)
        #expect(c.selectedTab == tabBefore)
        #expect(c.searchPath == searchBefore)
        #expect(c.bookmarksPath == bookmarksBefore)
        #expect(c.settingsPath == settingsBefore)
    }

    // MARK: - §4.4: 連続受信は受信順に置換され、最後の URL が最終状態となる

    @Test func handle_consecutiveDeepLinks_appliesLastReceivedAsFinalState() {
        let c = AppCoordinator()
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift")!)
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift/issues")!)
        #expect(c.selectedTab == .search)
        #expect(c.searchPath == [
            .repositoryDetail(appleSwift),
            .issueList(appleSwift)
        ])
    }

    // MARK: - AC-1.3 / AC-2.3: deeplink 後に pop すれば検索画面（path 空）に戻る

    @Test func searchPath_afterRepoDetailDeepLink_popsBackToSearchRoot() {
        let c = AppCoordinator()
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift")!)
        c.searchPath.removeLast()
        #expect(c.searchPath == [])
    }

    @Test func searchPath_afterRepoIssuesDeepLink_popsBackToSearchRootInTwoSteps() {
        let c = AppCoordinator()
        c.handle(deepLink: URL(string: "githubclient://repo/apple/swift/issues")!)
        c.searchPath.removeLast()
        #expect(c.searchPath == [.repositoryDetail(appleSwift)])
        c.searchPath.removeLast()
        #expect(c.searchPath == [])
    }
}
