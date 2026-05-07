import Foundation

nonisolated struct GitHubIssueDetail: Sendable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let body: String?
    let state: IssueState
    let user: GitHubUser
    let labels: [GitHubLabel]
    let commentsCount: Int
    let htmlUrl: URL
    let createdAt: Date
    let updatedAt: Date
}

nonisolated struct GitHubIssueComment: Sendable, Identifiable, Hashable {
    let id: Int
    let user: GitHubUser
    let body: String
    let createdAt: Date
}
