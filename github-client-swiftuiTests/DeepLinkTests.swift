import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct DeepLinkTests {

    // MARK: - 正常系 (AC-1.1 / AC-1.4 / AC-2.1 / AC-2.4 / §5.3)

    @Test func parse_repoDetail_buildsRepositoryDetailDeepLink() {
        let url = URL(string: "githubclient://repo/apple/swift")!
        #expect(DeepLink.parse(url) == .repositoryDetail(
            GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        ))
    }

    @Test func parse_repoIssues_buildsIssueListDeepLink() {
        let url = URL(string: "githubclient://repo/apple/swift/issues")!
        #expect(DeepLink.parse(url) == .issueList(
            GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        ))
    }

    @Test func parse_repoDetail_preservesOwnerNameCaseWithoutNormalization() {
        let url = URL(string: "githubclient://repo/Apple/Swift")!
        #expect(DeepLink.parse(url) == .repositoryDetail(
            GitHubRepoFullName(ownerLogin: "Apple", name: "Swift")
        ))
    }

    @Test func parse_repoIssues_preservesOwnerNameCaseWithoutNormalization() {
        let url = URL(string: "githubclient://repo/Apple/Swift/issues")!
        #expect(DeepLink.parse(url) == .issueList(
            GitHubRepoFullName(ownerLogin: "Apple", name: "Swift")
        ))
    }

    // AC-1.4 / AC-2.4: ASCII 以外（GitHub 規約外でも）を渡しても正規化しないことを示す。
    @Test func parse_repoDetail_preservesNonAsciiOwnerNameWithoutNormalization() {
        let url = URL(string: "githubclient://repo/%E6%97%A5%E6%9C%AC/%E3%83%86%E3%82%B9%E3%83%88")!
        #expect(DeepLink.parse(url) == .repositoryDetail(
            GitHubRepoFullName(ownerLogin: "日本", name: "テスト")
        ))
    }

    // MARK: - searchPath への変換 (§5.3)

    @Test func searchPath_forRepositoryDetail_isSingleRepositoryDetailRoute() {
        let fullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        let link: DeepLink = .repositoryDetail(fullName)
        #expect(link.searchPath == [.repositoryDetail(fullName)])
    }

    @Test func searchPath_forIssueList_isDetailThenIssueListRoutesWithSameFullName() {
        let fullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        let link: DeepLink = .issueList(fullName)
        #expect(link.searchPath == [
            .repositoryDetail(fullName),
            .issueList(fullName)
        ])
    }

    // MARK: - スキーム / host の大文字小文字 (§5.1)

    @Test func parse_mixedCaseScheme_isAcceptedCaseInsensitively() {
        // RFC 3986 / PRD §5.1: スキームは case-insensitive で扱う。
        #expect(DeepLink.parse(URL(string: "GithubClient://repo/apple/swift")!) == .repositoryDetail(
            GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        ))
        #expect(DeepLink.parse(URL(string: "GITHUBCLIENT://repo/apple/swift/issues")!) == .issueList(
            GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        ))
    }

    @Test func parse_mixedCaseHost_isAcceptedCaseInsensitively() {
        // host も RFC 3986 上 case-insensitive。スキームと同等に扱う。
        #expect(DeepLink.parse(URL(string: "githubclient://Repo/apple/swift")!) == .repositoryDetail(
            GitHubRepoFullName(ownerLogin: "apple", name: "swift")
        ))
    }

    // MARK: - 不正系: スキーム (AC-4.2)

    @Test func parse_nonGithubclientScheme_returnsNil() {
        #expect(DeepLink.parse(URL(string: "https://repo/apple/swift")!) == nil)
        #expect(DeepLink.parse(URL(string: "myapp://repo/apple/swift")!) == nil)
    }

    // MARK: - 不正系: host (AC-4.1)

    @Test func parse_hostOtherThanRepo_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://user/apple")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://issue/apple/swift")!) == nil)
    }

    // MARK: - パーセントエンコード境界 (§5.2 / §10 純粋関数性)

    // %2F (`/`) を含む owner / name は URLComponents.path 上で decode されてセグメントが
    // 分割されるため、実質的に階層数判定で弾かれることを意図として固定する。
    // GitHub の owner/name は仕様上 `/` を含まないため実害は無いが、境界挙動として明示する。
    @Test func parse_percentEncodedSlashInOwner_isRejectedAsInvalid() {
        // "foo%2Fbar/baz" は decode 後に 3 セグメント (foo, bar, baz) として扱われ、
        // 3 つ目が "issues" ではないので nil になる。
        #expect(DeepLink.parse(URL(string: "githubclient://repo/foo%2Fbar/baz")!) == nil)
    }

    // MARK: - 不正系: 階層数 (AC-4.1)

    @Test func parse_pathWithSingleSegment_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple")!) == nil)
    }

    @Test func parse_pathWithFourOrMoreSegments_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/issues/1")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/pulls")!) == nil)
    }

    @Test func parse_pathWithEmptyPath_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/")!) == nil)
    }

    // MARK: - 不正系: 3 番目セグメント (AC-4.1)

    @Test func parse_thirdSegmentNotIssues_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/pulls")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/Issues")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/ISSUES")!) == nil)
    }

    // MARK: - 不正系: 空成分 (AC-4.1)

    @Test func parse_trailingSlash_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/issues/")!) == nil)
    }

    @Test func parse_consecutiveSlashes_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo//swift")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple//issues")!) == nil)
    }

    // MARK: - 不正系: クエリ・フラグメント (AC-4.1)

    @Test func parse_withQuery_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift?ref=main")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/issues?state=open")!) == nil)
    }

    @Test func parse_withFragment_returnsNil() {
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift#readme")!) == nil)
        #expect(DeepLink.parse(URL(string: "githubclient://repo/apple/swift/issues#top")!) == nil)
    }
}
