import Foundation

nonisolated final class MockRepositorySearchRepository: RepositorySearchRepositoryProtocol, @unchecked Sendable {
    var result: Result<[GitHubRepo], Error>
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

    init(result: Result<[GitHubRepo], Error>) {
        self.result = result
    }

    convenience init() {
        self.init(result: .success(GitHubRepo.samples))
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepo] {
        searchCallCount += 1
        lastQuery = query
        lastPage = page
        return try result.get()
    }
}
