import Foundation

nonisolated struct GitHubRepo: Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
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
