import Foundation

nonisolated struct GitHubIssue: Sendable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let state: IssueState
    let user: GitHubUser
    let labels: [GitHubLabel]
    let commentsCount: Int
    let createdAt: Date
    let isPullRequest: Bool
}

nonisolated enum IssueState: String, Sendable, Hashable, Codable {
    case open
    case closed
}

nonisolated struct GitHubUser: Sendable, Hashable {
    let login: String
    let id: Int
    let avatarUrl: URL?
    let htmlUrl: URL
}

nonisolated struct GitHubLabel: Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let color: String
}
