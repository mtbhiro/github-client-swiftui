import Foundation

enum DeepLink: Hashable, Sendable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)

    static func parse(_ url: URL) -> DeepLink? {
        // RFC 3986 に従いスキーム / host は case-insensitive で比較する（PRD §5.1）。
        guard url.scheme?.lowercased() == "githubclient" else { return nil }
        guard url.host?.lowercased() == "repo" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard components.query == nil, components.fragment == nil else { return nil }

        // URLComponents.path は末尾スラッシュ・連続スラッシュを保持する生のパスを返す。
        // 先頭 "/" を除いた残りを "/" で分割すれば、空成分は空文字として現れるため
        // §4.3.1 の「空成分があれば invalid」判定が一様にできる。
        let rawPath = components.path
        guard rawPath.hasPrefix("/") else { return nil }
        let segments = rawPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        guard !segments.contains(where: \.isEmpty) else { return nil }

        switch segments.count {
        case 2:
            return .repositoryDetail(GitHubRepoFullName(ownerLogin: segments[0], name: segments[1]))
        case 3 where segments[2] == "issues":
            return .issueList(GitHubRepoFullName(ownerLogin: segments[0], name: segments[1]))
        default:
            return nil
        }
    }

    var searchPath: [ContentRoute] {
        switch self {
        case let .repositoryDetail(fullName):
            return [.repositoryDetail(fullName)]
        case let .issueList(fullName):
            return [.repositoryDetail(fullName), .issueList(fullName)]
        }
    }
}
