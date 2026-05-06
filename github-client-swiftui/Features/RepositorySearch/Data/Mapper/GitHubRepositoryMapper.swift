import Foundation

nonisolated enum GitHubRepositoryMapper {
    static func map(_ dto: GitHubRepositoryDTO) -> GitHubRepository {
        GitHubRepository(
            id: dto.id,
            name: dto.name,
            fullName: dto.fullName,
            owner: GitHubRepositoryOwner(
                login: dto.owner.login,
                id: dto.owner.id,
                avatarUrl: URL(string: dto.owner.avatarUrl),
                htmlUrl: URL(string: dto.owner.htmlUrl)!
            ),
            description: dto.description,
            htmlUrl: URL(string: dto.htmlUrl)!,
            stargazersCount: dto.stargazersCount,
            forksCount: dto.forksCount,
            language: dto.language,
            topics: dto.topics ?? []
        )
    }

    static func map(_ dto: GitHubSearchResponseDTO) -> [GitHubRepository] {
        dto.items.map { map($0) }
    }
}
