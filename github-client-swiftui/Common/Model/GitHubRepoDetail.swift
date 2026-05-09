import Foundation

nonisolated struct GitHubRepoDetail: Sendable, Identifiable, Hashable {
    var id: GitHubRepoFullName { fullName }
    let fullName: GitHubRepoFullName
    let owner: GitHubRepoOwner
    let description: String?
    let htmlUrl: URL
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let language: String?
    let topics: [String]
    let defaultBranch: String
    let createdAt: Date
    let updatedAt: Date
}
