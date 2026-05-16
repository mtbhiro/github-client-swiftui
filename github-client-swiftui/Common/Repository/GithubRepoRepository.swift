import Foundation

nonisolated protocol GithubRepoRepositoryProtocol: Sendable {
    func searchRepositories(
        query: String,
        sort: String?,
        order: String?,
        page: Int
    ) async throws -> RepositorySearchPageResult
    func fetchRepository(fullName: GitHubRepoFullName) async throws -> GitHubRepoDetail
    func fetchIssues(fullName: GitHubRepoFullName, page: Int) async throws -> [GitHubIssue]
    func fetchIssueDetail(fullName: GitHubRepoFullName, number: Int) async throws -> GitHubIssueDetail
    func fetchIssueComments(fullName: GitHubRepoFullName, number: Int, page: Int) async throws -> [GitHubIssueComment]
}

nonisolated struct GithubRepoRepository: GithubRepoRepositoryProtocol {
    private let httpClient: HttpClient

    init(httpClient: HttpClient = URLSessionHttpClient()) {
        self.httpClient = httpClient
    }

    func searchRepositories(
        query: String,
        sort: String?,
        order: String?,
        page: Int
    ) async throws -> RepositorySearchPageResult {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: "30"),
        ]
        if let sort {
            queryItems.append(URLQueryItem(name: "sort", value: sort))
        }
        if let order {
            queryItems.append(URLQueryItem(name: "order", value: order))
        }

        let request = HttpRequest(path: "/search/repositories", queryItems: queryItems)
        let response: GitHubSearchResponseDTO = try await httpClient.send(request)
        return RepositorySearchPageResult(
            repositories: response.toDomain(),
            totalCount: response.totalCount,
            incompleteResults: response.incompleteResults
        )
    }

    func fetchRepository(fullName: GitHubRepoFullName) async throws -> GitHubRepoDetail {
        let request = HttpRequest(path: "/repos/\(fullName.ownerLogin)/\(fullName.name)")
        let response: GitHubRepoDetailDTO = try await httpClient.send(request)
        return response.toDomain()
    }

    func fetchIssues(fullName: GitHubRepoFullName, page: Int) async throws -> [GitHubIssue] {
        let request = HttpRequest(
            path: "/repos/\(fullName.ownerLogin)/\(fullName.name)/issues",
            queryItems: [
                URLQueryItem(name: "state", value: "all"),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "30"),
            ]
        )
        let response: [GitHubIssueDTO] = try await httpClient.send(request)
        return response.map { $0.toDomain() }
    }

    func fetchIssueDetail(fullName: GitHubRepoFullName, number: Int) async throws -> GitHubIssueDetail {
        let request = HttpRequest(path: "/repos/\(fullName.ownerLogin)/\(fullName.name)/issues/\(number)")
        let response: GitHubIssueDetailDTO = try await httpClient.send(request)
        return response.toDomain()
    }

    func fetchIssueComments(fullName: GitHubRepoFullName, number: Int, page: Int) async throws -> [GitHubIssueComment] {
        let request = HttpRequest(
            path: "/repos/\(fullName.ownerLogin)/\(fullName.name)/issues/\(number)/comments",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "30"),
            ]
        )
        let response: [GitHubIssueCommentDTO] = try await httpClient.send(request)
        return response.map { $0.toDomain() }
    }
}
