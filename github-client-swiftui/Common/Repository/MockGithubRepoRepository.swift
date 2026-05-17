import Foundation

actor MockGithubRepoRepository: GithubRepoRepositoryProtocol {
    var searchResult: Result<RepositorySearchPageResult, Error>
    var searchResultHandler: (@Sendable (String, String?, String?, Int) -> Result<RepositorySearchPageResult, Error>)?
    var fetchResult: Result<GitHubRepoDetail, Error>
    var issuesResult: Result<[GitHubIssue], Error>
    var issuesResultHandler: (@Sendable (GitHubRepoFullName, Int) -> Result<[GitHubIssue], Error>)?
    var issueDetailResult: Result<GitHubIssueDetail, Error>
    var issueCommentsResult: Result<[GitHubIssueComment], Error>
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastSort: String?
    private(set) var lastOrder: String?
    private(set) var lastPage: Int?

    init(
        searchResult: Result<RepositorySearchPageResult, Error> = .success(
            RepositorySearchPageResult(repositories: GitHubRepo.samples, totalCount: GitHubRepo.samples.count, incompleteResults: false)
        ),
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

    func setSearchResult(_ result: Result<RepositorySearchPageResult, Error>) {
        searchResult = result
    }

    func setSearchResultHandler(_ handler: (@Sendable (String, String?, String?, Int) -> Result<RepositorySearchPageResult, Error>)?) {
        searchResultHandler = handler
    }

    func setIssuesResult(_ result: Result<[GitHubIssue], Error>) {
        issuesResult = result
    }

    func setIssuesResultHandler(_ handler: (@Sendable (GitHubRepoFullName, Int) -> Result<[GitHubIssue], Error>)?) {
        issuesResultHandler = handler
    }

    func setFetchResult(_ result: Result<GitHubRepoDetail, Error>) {
        fetchResult = result
    }

    func setIssueDetailResult(_ result: Result<GitHubIssueDetail, Error>) {
        issueDetailResult = result
    }

    func setIssueCommentsResult(_ result: Result<[GitHubIssueComment], Error>) {
        issueCommentsResult = result
    }

    func searchRepositories(
        query: String,
        sort: String?,
        order: String?,
        page: Int
    ) async throws -> RepositorySearchPageResult {
        searchCallCount += 1
        lastQuery = query
        lastSort = sort
        lastOrder = order
        lastPage = page
        if let handler = searchResultHandler {
            return try handler(query, sort, order, page).get()
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
