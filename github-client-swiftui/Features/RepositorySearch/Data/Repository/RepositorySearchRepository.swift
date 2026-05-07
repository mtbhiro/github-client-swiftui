import Foundation

nonisolated protocol RepositorySearchRepositoryProtocol: Sendable {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepo]
}

nonisolated struct RepositorySearchRepository: RepositorySearchRepositoryProtocol {
    private let httpClient: HttpClient

    init(httpClient: HttpClient) {
        self.httpClient = httpClient
    }

    init() {
        self.httpClient = GitHubHttpClient.shared
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
}
