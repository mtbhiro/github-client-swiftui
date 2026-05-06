import Foundation

nonisolated struct GitHubRepository: Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GitHubRepositoryOwner
    let description: String?
    let htmlUrl: URL
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let topics: [String]
}

nonisolated struct GitHubRepositoryOwner: Sendable, Hashable {
    let login: String
    let id: Int
    let avatarUrl: URL?
    let htmlUrl: URL
}
