import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchModelTests {

    private func makeSUT(
        result: Result<[GitHubRepo], Error>? = nil,
        debounceDuration: Duration = .milliseconds(0)
    ) -> (model: RepositorySearchModel, mock: MockGithubRepoRepository) {
        let mock = MockGithubRepoRepository(
            searchResult: result ?? .success(GitHubRepo.samples)
        )
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: debounceDuration
        )
        return (model, mock)
    }

    @Test func initialState_isIdle() {
        let (model, _) = makeSUT()
        #expect(model.query == "")
        #expect(model.phase == .idle)
        #expect(model.repositories.isEmpty)
    }

    @Test func settingEmptyQuery_remainsIdle() {
        let (model, _) = makeSUT()
        model.query = "   "
        #expect(model.phase == .idle)
    }

    @Test func settingQuery_transitionsToLoading() {
        let (model, _) = makeSUT()
        model.query = "swift"
        #expect(model.phase == .loading)
    }

    @Test func clearQuery_resetsToIdle() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.clearQuery()
        #expect(model.query == "")
        #expect(model.phase == .idle)
        #expect(model.repositories.isEmpty)
    }

    @Test func onSubmit_transitionsToLoading() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.onSubmit()
        #expect(model.phase == .loading)
    }

    @Test func onDisappear_cancelsSearch() async {
        let (model, _) = makeSUT(debounceDuration: .seconds(10))
        model.query = "swift"
        model.onDisappear()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loading)
    }

    @Test func retry_startsSearchAgain() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.retry()
        #expect(model.phase == .loading)
    }

    @Test func search_success_loadsRepositories() async throws {
        let (model, mock) = makeSUT()
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loaded(isEmpty: false))
        #expect(model.repositories == GitHubRepo.samples)
        #expect(mock.lastQuery == "swift")
        #expect(mock.lastPage == 1)
        #expect(model.hasMorePages == false)
    }

    @Test func search_emptyResult_loadsEmpty() async throws {
        let (model, _) = makeSUT(result: .success([]))
        model.query = "nonexistent"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loaded(isEmpty: true))
        #expect(model.repositories.isEmpty)
    }

    @Test func search_failure_showsError() async throws {
        let (model, _) = makeSUT(result: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        guard case .error = model.phase else {
            Issue.record("Expected error phase")
            return
        }
    }

    @Test func queryChange_debounces() async throws {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(100))
        model.query = "s"
        model.query = "sw"
        model.query = "swi"
        #expect(model.phase == .loading)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mock.searchCallCount == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.searchCallCount == 1)
        #expect(mock.lastQuery == "swi")
    }

    @Test func newSearch_cancelsPrevious() async throws {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(50))
        model.query = "first"
        try await Task.sleep(for: .milliseconds(30))
        model.query = "second"
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.lastQuery == "second")
    }

    // MARK: - Pagination

    @Test func search_fullPage_setsHasMorePages() async throws {
        let fullPage = makeRepos(count: 30)
        let (model, _) = makeSUT(result: .success(fullPage))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hasMorePages == true)
        #expect(model.repositories.count == 30)
    }

    @Test func loadNextPageIfNeeded_loadsNextPage() async throws {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 10, startId: 31)
        let (model, mock) = makeSUT(result: .success(page1))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hasMorePages == true)

        mock.searchResult = .success(page2)
        model.loadNextPageIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.repositories.count == 40)
        #expect(mock.lastPage == 2)
        #expect(model.hasMorePages == false)
        #expect(model.isLoadingMore == false)
    }

    @Test func loadNextPageIfNeeded_doesNothingWhenNoMorePages() async throws {
        let (model, mock) = makeSUT()
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hasMorePages == false)

        let callCountBefore = mock.searchCallCount
        model.loadNextPageIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(mock.searchCallCount == callCountBefore)
    }

    @Test func loadNextPageIfNeeded_doesNothingWhileAlreadyLoading() async throws {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(result: .success(page1))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))

        mock.searchResult = .success(makeRepos(count: 30, startId: 31))
        model.loadNextPageIfNeeded()
        let callCountAfterFirst = mock.searchCallCount
        model.loadNextPageIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(mock.searchCallCount == callCountAfterFirst)
    }

    @Test func newSearch_resetsPagination() async throws {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(result: .success(page1))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.hasMorePages == true)

        let newPage1 = makeRepos(count: 5, startId: 100)
        mock.searchResult = .success(newPage1)
        model.query = "rust"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.repositories.count == 5)
        #expect(model.hasMorePages == false)
        #expect(mock.lastPage == 1)
    }

    @Test func loadNextPage_error_keepsExistingData() async throws {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(result: .success(page1))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))

        mock.searchResult = .failure(URLError(.notConnectedToInternet))
        model.loadNextPageIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.repositories.count == 30)
        #expect(model.phase == .loaded(isEmpty: false))
        #expect(model.isLoadingMore == false)
    }

    private func makeRepos(count: Int, startId: Int = 1) -> [GitHubRepo] {
        (startId..<startId + count).map { id in
            GitHubRepo(
                id: id,
                name: "repo-\(id)",
                fullName: "owner/repo-\(id)",
                owner: .sampleApple,
                description: nil,
                htmlUrl: URL(string: "https://github.com/owner/repo-\(id)")!,
                stargazersCount: 0,
                forksCount: 0,
                language: nil,
                topics: []
            )
        }
    }
}
