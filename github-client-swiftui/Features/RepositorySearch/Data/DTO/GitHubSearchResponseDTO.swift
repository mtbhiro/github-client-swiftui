import Foundation

nonisolated struct GitHubSearchResponseDTO: Decodable, Sendable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [GitHubRepoDTO]

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case incompleteResults = "incomplete_results"
        case items
    }

    func toDomain() throws -> [GitHubRepo] {
        try items.map { try $0.toDomain() }
    }
}

nonisolated struct GitHubRepoDTO: Decodable, Sendable {
    let id: Int
    let name: String
    let fullName: String
    let owner: GitHubOwnerDTO
    let description: String?
    let htmlUrl: String
    let stargazersCount: Int
    let forksCount: Int
    let language: String?
    let topics: [String]?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case description
        case htmlUrl = "html_url"
        case stargazersCount = "stargazers_count"
        case forksCount = "forks_count"
        case language
        case topics
    }

    func toDomain() throws -> GitHubRepo {
        guard let ownerHtmlUrl = URL(string: owner.htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "owner.htmlUrl", value: owner.htmlUrl)
        }
        guard let repoHtmlUrl = URL(string: htmlUrl) else {
            throw DTOMappingError.invalidURL(field: "htmlUrl", value: htmlUrl)
        }
        return GitHubRepo(
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
            forksCount: forksCount,
            language: language,
            topics: topics ?? []
        )
    }
}

nonisolated struct GitHubOwnerDTO: Decodable, Sendable {
    let login: String
    let id: Int
    let avatarUrl: String
    let htmlUrl: String

    private enum CodingKeys: String, CodingKey {
        case login
        case id
        case avatarUrl = "avatar_url"
        case htmlUrl = "html_url"
    }
}
