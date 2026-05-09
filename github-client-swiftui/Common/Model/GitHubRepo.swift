import Foundation

nonisolated struct GitHubRepo: Sendable, Identifiable, Hashable {
    var id: GitHubRepoFullName { fullName }
    let fullName: GitHubRepoFullName
    let owner: GitHubRepoOwner
    let description: String?
    let htmlUrl: URL
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let topics: [String]
}

nonisolated struct GitHubRepoOwner: Sendable, Hashable {
    let login: String
    let id: Int
    let avatarUrl: URL?
    let htmlUrl: URL
}
