import Foundation

final class MockRepositorySearchRepository: RepositorySearchRepositoryProtocol, @unchecked Sendable {
    nonisolated init() {}

    var result: Result<[GitHubRepository], Error> = .success(GitHubRepository.samples)
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        searchCallCount += 1
        lastQuery = query
        lastPage = page
        return try result.get()
    }
}
