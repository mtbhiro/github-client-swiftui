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

    func toDomain() throws -> GitHubRepoDetail {
        guard let ownerHtmlUrl = URL(string: owner.htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "owner.htmlUrl", value: owner.htmlUrl)
        }
        guard let repoHtmlUrl = URL(string: htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "htmlUrl", value: htmlUrl)
        }
        guard let parsedCreatedAt = DateFormatters.iso8601.date(from: createdAt) else {
            throw DTOMappingError.invalidDate(field: "createdAt", value: createdAt)
        }
        guard let parsedUpdatedAt = DateFormatters.iso8601.date(from: updatedAt) else {
            throw DTOMappingError.invalidDate(field: "updatedAt", value: updatedAt)
        }
        return GitHubRepoDetail(
            fullName: GitHubRepoFullName(ownerLogin: owner.login, name: name),
            owner: GitHubRepoOwner(
                login: owner.login,
                id: owner.id,
                avatarUrl: URL(string: owner.avatarUrl),
                htmlUrl: ownerHtmlUrl
            ),
            description: description,
            htmlUrl: repoHtmlUrl,
            stargazersCount: stargazersCount,
            watchersCount: watchersCount,
            forksCount: forksCount,
            openIssuesCount: openIssuesCount,
            language: language,
            topics: topics ?? [],
            defaultBranch: defaultBranch,
            createdAt: parsedCreatedAt,
            updatedAt: parsedUpdatedAt
        )
    }
}
