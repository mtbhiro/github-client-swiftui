import Foundation

nonisolated final class MockGithubRepoRepository: GithubRepoRepositoryProtocol, @unchecked Sendable {
    var searchResult: Result<[GitHubRepo], Error>
    var searchResultHandler: ((String, Int) -> Result<[GitHubRepo], Error>)?
    var fetchResult: Result<GitHubRepoDetail, Error>
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

    init(
        searchResult: Result<[GitHubRepo], Error> = .success(GitHubRepo.samples),
        fetchResult: Result<GitHubRepoDetail, Error> = .success(.sampleSwift)
    ) {
        self.searchResult = searchResult
        self.fetchResult = fetchResult
    }

    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepo] {
        searchCallCount += 1
        lastQuery = query
        lastPage = page
        if let handler = searchResultHandler {
            return try handler(query, page).get()
        }
        return try searchResult.get()
    }

    func fetchRepository(owner: String, name: String) async throws -> GitHubRepoDetail {
        try fetchResult.get()
    }
}
