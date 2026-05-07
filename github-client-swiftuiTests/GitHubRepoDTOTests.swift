import Testing
import Foundation
@testable import github_client_swiftui

@MainActor
struct GitHubRepoDTOTests {

    @Test func toDomain_convertsCorrectly() {
        let ownerDTO = GitHubOwnerDTO(
            login: "apple",
            id: 10639145,
            avatarUrl: "https://avatars.githubusercontent.com/u/10639145?v=4",
            htmlUrl: "https://github.com/apple"
        )
        let repoDTO = GitHubRepoDTO(
            id: 44838949,
            name: "swift",
            fullName: "apple/swift",
            owner: ownerDTO,
            description: "The Swift Programming Language",
            htmlUrl: "https://github.com/apple/swift",
            stargazersCount: 67000,
            forksCount: 10300,
            language: "C++",
            topics: ["swift", "compiler"]
        )

        let repo = repoDTO.toDomain()

        #expect(repo.id == 44838949)
        #expect(repo.name == "swift")
        #expect(repo.fullName == "apple/swift")
        #expect(repo.owner.login == "apple")
        #expect(repo.owner.id == 10639145)
        #expect(repo.owner.avatarUrl?.absoluteString == "https://avatars.githubusercontent.com/u/10639145?v=4")
        #expect(repo.description == "The Swift Programming Language")
        #expect(repo.htmlUrl.absoluteString == "https://github.com/apple/swift")
        #expect(repo.stargazersCount == 67000)
        #expect(repo.forksCount == 10300)
        #expect(repo.language == "C++")
        #expect(repo.topics == ["swift", "compiler"])
    }

    @Test func toDomain_nilTopics_becomesEmptyArray() {
        let ownerDTO = GitHubOwnerDTO(
            login: "test",
            id: 1,
            avatarUrl: "https://example.com/avatar.png",
            htmlUrl: "https://github.com/test"
        )
        let repoDTO = GitHubRepoDTO(
            id: 1,
            name: "test",
            fullName: "test/test",
            owner: ownerDTO,
            description: nil,
            htmlUrl: "https://github.com/test/test",
            stargazersCount: 0,
            forksCount: 0,
            language: nil,
            topics: nil
        )

        let repo = repoDTO.toDomain()

        #expect(repo.topics.isEmpty)
        #expect(repo.description == nil)
        #expect(repo.language == nil)
    }

    @Test func searchResponseToDomain_convertsAllItems() {
        let ownerDTO = GitHubOwnerDTO(
            login: "org",
            id: 1,
            avatarUrl: "https://example.com/a.png",
            htmlUrl: "https://github.com/org"
        )
        let response = GitHubSearchResponseDTO(
            totalCount: 2,
            incompleteResults: false,
            items: [
                GitHubRepoDTO(
                    id: 1, name: "repo1", fullName: "org/repo1",
                    owner: ownerDTO, description: "First",
                    htmlUrl: "https://github.com/org/repo1",
                    stargazersCount: 100, forksCount: 10,
                    language: "Swift", topics: ["ios"]
                ),
                GitHubRepoDTO(
                    id: 2, name: "repo2", fullName: "org/repo2",
                    owner: ownerDTO, description: "Second",
                    htmlUrl: "https://github.com/org/repo2",
                    stargazersCount: 200, forksCount: 20,
                    language: "Kotlin", topics: nil
                ),
            ]
        )

        let repos = response.toDomain()

        #expect(repos.count == 2)
        #expect(repos[0].name == "repo1")
        #expect(repos[1].name == "repo2")
        #expect(repos[1].topics.isEmpty)
    }

    @Test func decodingJSON_parsesCorrectly() throws {
        let json = """
        {
            "total_count": 1,
            "incomplete_results": false,
            "items": [
                {
                    "id": 123,
                    "name": "example",
                    "full_name": "user/example",
                    "owner": {
                        "login": "user",
                        "id": 456,
                        "avatar_url": "https://example.com/avatar.png",
                        "html_url": "https://github.com/user"
                    },
                    "description": "An example repo",
                    "html_url": "https://github.com/user/example",
                    "stargazers_count": 42,
                    "forks_count": 7,
                    "language": "Swift",
                    "topics": ["swift", "example"]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GitHubSearchResponseDTO.self, from: json)

        #expect(decoded.totalCount == 1)
        #expect(decoded.incompleteResults == false)
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].id == 123)
        #expect(decoded.items[0].fullName == "user/example")
        #expect(decoded.items[0].owner.login == "user")
        #expect(decoded.items[0].owner.avatarUrl == "https://example.com/avatar.png")
        #expect(decoded.items[0].stargazersCount == 42)
        #expect(decoded.items[0].topics == ["swift", "example"])
    }
}
