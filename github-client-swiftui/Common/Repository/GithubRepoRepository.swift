import Foundation

nonisolated protocol GithubRepoRepositoryProtocol: Sendable {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepo]
    func fetchRepository(owner: String, name: String) async throws -> GitHubRepoDetail
}

nonisolated struct GithubRepoRepository: GithubRepoRepositoryProtocol {
    private let httpClient: HttpClient

    init(httpClient: HttpClient = URLSessionHttpClient()) {
        self.httpClient = httpClient
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepo] {
        let request = HttpRequest(
            path: "/search/repositories",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "30"),
            ]
        )
        let response: GitHubSearchResponseDTO = try await httpClient.send(request)
        return response.toDomain()
    }

    func fetchRepository(owner: String, name: String) async throws -> GitHubRepoDetail {
        let request = HttpRequest(path: "/repos/\(owner)/\(name)")
        let response: GitHubRepoDetailDTO = try await httpClient.send(request)
        return response.toDomain()
    }
}
