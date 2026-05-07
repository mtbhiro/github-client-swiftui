import Foundation

nonisolated struct GitHubRepoDetail: Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
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
