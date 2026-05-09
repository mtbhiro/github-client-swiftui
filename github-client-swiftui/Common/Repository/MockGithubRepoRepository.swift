import Foundation

nonisolated final class MockGithubRepoRepository: GithubRepoRepositoryProtocol, @unchecked Sendable {
    var searchResult: Result<[GitHubRepo], Error>
    var searchResultHandler: ((String, Int) -> Result<[GitHubRepo], Error>)?
    var fetchResult: Result<GitHubRepoDetail, Error>
    var issuesResult: Result<[GitHubIssue], Error>
    var issuesResultHandler: ((GitHubRepoFullName, Int) -> Result<[GitHubIssue], Error>)?
    var issueDetailResult: Result<GitHubIssueDetail, Error>
    var issueCommentsResult: Result<[GitHubIssueComment], Error>
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

    init(
        searchResult: Result<[GitHubRepo], Error> = .success(GitHubRepo.samples),
        fetchResult: Result<GitHubRepoDetail, Error> = .success(.sampleSwift),
        issuesResult: Result<[GitHubIssue], Error> = .success(GitHubIssue.samples),
        issueDetailResult: Result<GitHubIssueDetail, Error> = .success(.sample),
        issueCommentsResult: Result<[GitHubIssueComment], Error> = .success(GitHubIssueComment.samples)
    ) {
        self.searchResult = searchResult
        self.fetchResult = fetchResult
        self.issuesResult = issuesResult
        self.issueDetailResult = issueDetailResult
        self.issueCommentsResult = issueCommentsResult
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

    func fetchRepository(fullName: GitHubRepoFullName) async throws -> GitHubRepoDetail {
        try fetchResult.get()
    }

    func fetchIssues(fullName: GitHubRepoFullName, page: Int) async throws -> [GitHubIssue] {
        if let handler = issuesResultHandler {
            return try handler(fullName, page).get()
        }
        return try issuesResult.get()
    }

    func fetchIssueDetail(fullName: GitHubRepoFullName, number: Int) async throws -> GitHubIssueDetail {
        try issueDetailResult.get()
    }

    func fetchIssueComments(fullName: GitHubRepoFullName, number: Int, page: Int) async throws -> [GitHubIssueComment] {
        try issueCommentsResult.get()
    }
}
