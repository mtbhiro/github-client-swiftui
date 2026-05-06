import Foundation

nonisolated final class MockRepositorySearchRepository: RepositorySearchRepositoryProtocol, @unchecked Sendable {
    var result: Result<[GitHubRepository], Error>
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

    init(result: Result<[GitHubRepository], Error>) {
        self.result = result
    }

    convenience init() {
        self.init(result: .success(GitHubRepository.samples))
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository] {
        searchCallCount += 1
        lastQuery = query
        lastPage = page
        return try result.get()
    }
}
