import Foundation

nonisolated struct GitHubRepoDetailDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GitHubOwnerDTO
    let description: String?
    let htmlUrl: String
    let stargazersCount: Int
    let watchersCount: Int
    let forksCount: Int
    let openIssuesCount: Int
    let language: String?
    let topics: [String]?
    let defaultBranch: String
    let createdAt: String
    let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case description
        case htmlUrl = "html_url"
        case stargazersCount = "stargazers_count"
        case watchersCount = "watchers_count"
        case forksCount = "forks_count"
        case openIssuesCount = "open_issues_count"
        case language
        case topics
        case defaultBranch = "default_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> GitHubRepoDetail {
        let formatter = ISO8601DateFormatter()
        return GitHubRepoDetail(
            id: id,
            name: name,
            fullName: fullName,
            owner: GitHubRepoOwner(
                login: owner.login,
                id: owner.id,
                avatarUrl: URL(string: owner.avatarUrl),
                htmlUrl: URL(string: owner.htmlUrl)!
            ),
            description: description,
            htmlUrl: URL(string: htmlUrl)!,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            language: language,
            topics: topics ?? [],
            defaultBranch: defaultBranch,
            createdAt: formatter.date(from: createdAt) ?? .distantPast,
            updatedAt: formatter.date(from: updatedAt) ?? .distantPast
        )
    }
}
