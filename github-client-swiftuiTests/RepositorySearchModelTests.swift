import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
@Suite(.serialized)
struct RepositorySearchModelTests {

    // MARK: - Helpers

    private func makeSUT(
        searchResult: Result<RepositorySearchPageResult, Error>? = nil,
        debounceDuration: Duration = .milliseconds(0)
    ) -> (model: RepositorySearchModel, mock: MockGithubRepoRepository) {
        let mock = MockGithubRepoRepository(
            searchResult: searchResult ?? .success(.init(repositories: GitHubRepo.samples, totalCount: GitHubRepo.samples.count, incompleteResults: false))
        )
        let suiteName = "RepositorySearchModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = RepositorySearchConditionStore(defaults: defaults)
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: debounceDuration,
            conditionStore: store
        )
        return (model, mock)
    }

    private func makeRepos(count: Int, startId: Int = 1) -> [GitHubRepo] {
        (startId..<startId + count).map { id in
            GitHubRepo(
                fullName: GitHubRepoFullName(ownerLogin: "owner", name: "repo-\(id)"),
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

    private func waitTick(_ ms: Int = 50) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: - US-1: idle / loading / loaded / no-results

    @Test func initialState_isIdleAndDoesNotCallApi() async {
        let (model, mock) = makeSUT()
        await waitTick()
        #expect(model.phase == .idle)
        await #expect(mock.searchCallCount == 0)
    }

    @Test func typingQuery_afterDebounce_fires_loading_thenLoaded() async {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(100))
        model.query = "swift"
        // 入力直後はまだ API 未発火、ただし loading に切り替わる
        // (前の結果を即時クリアして loading 画面に切り替える PRD §4.2 の意図)
        #expect(model.phase == .loading)
        await waitTick(50)
        await #expect(mock.searchCallCount == 0)
        await waitTick(100)
        await #expect(mock.searchCallCount == 1)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.repositories == GitHubRepo.samples)
    }

    @Test func rapidTyping_resetsDebounceTimer_andCancelsPrevious() async {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(100))
        model.query = "s"
        model.query = "sw"
        model.query = "swi"
        await waitTick(50)
        await #expect(mock.searchCallCount == 0)
        await waitTick(100)
        await #expect(mock.searchCallCount == 1)
        await #expect(mock.lastQuery == "swi")
    }

    @Test func emptyResult_transitionsToNoResults() async {
        let (model, _) = makeSUT(searchResult: .success(.init(repositories: [], totalCount: 0, incompleteResults: false)))
        model.query = "nonexistent"
        await waitTick()
        guard case let .noResults(q) = model.phase else {
            Issue.record("Expected noResults phase, got \(model.phase)")
            return
        }
        #expect(q == "nonexistent")
    }

    @Test func clearingQuery_resetsToIdle_andCancelsRequest() async {
        let (model, _) = makeSUT()
        model.query = "swift"
        await waitTick()
        model.query = ""
        await waitTick()
        #expect(model.phase == .idle)
    }

    // MARK: - US-2: qualifier 適用

    @Test func applyingQualifiers_firesSearch_andUpdatesChips() async {
        let (model, mock) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        model.query = "ui"
        await waitTick()

        let baseline = await mock.searchCallCount
        model.applyQualifiers(q)
        await waitTick()

        await #expect(mock.searchCallCount == baseline + 1)
        await #expect(mock.lastQuery?.contains("language:Swift") == true)
        #expect(model.appliedQualifiers.language == GitHubLanguage(name: "Swift"))
    }

    @Test func removingChip_firesSearch() async {
        let (model, mock) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        q.topics = ["ios"]
        model.query = "ui"
        model.applyQualifiers(q)
        await waitTick()

        let baseline = await mock.searchCallCount
        model.removeChip(.language(label: "Swift"))
        await waitTick()

        await #expect(mock.searchCallCount == baseline + 1)
        #expect(model.appliedQualifiers.language == nil)
    }

    @Test func removingLastChip_withEmptyKeyword_returnsToIdle() async {
        let (model, _) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        model.applyQualifiers(q)
        await waitTick()
        #expect(model.query == "")

        model.removeChip(.language(label: "Swift"))
        await waitTick()
        #expect(model.phase == .idle)
    }

    // MARK: - US-3: ソート

    @Test func defaultSort_isStarsDesc() {
        let (model, _) = makeSUT()
        #expect(model.sort == RepositorySearchSort(key: .stars, order: .desc))
    }

    @Test func changingSort_clearsResults_andRefetches() async {
        let (model, mock) = makeSUT()
        model.query = "swift"
        await waitTick()

        let baseline = await mock.searchCallCount
        model.setSort(.init(key: .updated, order: .desc))
        #expect(model.phase == .loading)
        await waitTick()

        await #expect(mock.searchCallCount == baseline + 1)
        await #expect(mock.lastSort == "updated")
    }

    @Test func changingSort_withEmptyQueryAndNoQualifiers_doesNotFire() async {
        let (model, mock) = makeSUT()
        model.setSort(.init(key: .updated, order: .asc))
        await waitTick()
        await #expect(mock.searchCallCount == 0)
        #expect(model.phase == .idle)
    }

    // MARK: - US-4: ページング

    @Test func search_fullPage_setsHasMorePages() async {
        let fullPage = makeRepos(count: 30)
        let (model, _) = makeSUT(searchResult: .success(.init(repositories: fullPage, totalCount: 1000, incompleteResults: false)))
        model.query = "swift"
        await waitTick()
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.hasMorePages == true)
        #expect(state.repositories.count == 30)
    }

    @Test func loadNextPage_appendsResults() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 10, startId: 31)
        let (model, mock) = makeSUT(searchResult: .success(.init(repositories: page1, totalCount: 40, incompleteResults: false)))
        model.query = "swift"
        await waitTick()

        await mock.setSearchResult(.success(.init(repositories: page2, totalCount: 40, incompleteResults: false)))
        model.loadNextPageIfNeeded()
        await waitTick()

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.repositories.count == 40)
        #expect(state.hasMorePages == false)
        await #expect(mock.lastPage == 2)
    }

    @Test func loadNextPage_isCappedAt1000Items_andStopsRequestingFurther() async {
        // 各ページが 30 件返り続けるシナリオ。
        // 1 ページ目 (30 件) → ページング 33 回で 30 * 34 = 1020 件 → cap で 1000 件に切られる。
        // cap に達した時点で hasMorePages が false になり、それ以上のページング要求は発生しない (AC-4.4)。
        let page = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(searchResult: .success(.init(repositories: page, totalCount: 100000, incompleteResults: false)))
        model.query = "swift"
        await waitTick()

        for i in 2...34 {
            await mock.setSearchResult(.success(.init(repositories: makeRepos(count: 30, startId: i * 100), totalCount: 100000, incompleteResults: false)))
            model.loadNextPageIfNeeded()
            await waitTick(20)
        }

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.repositories.count == RepositorySearchModel.maxAccumulated)
        #expect(state.hasMorePages == false)

        // cap 後にさらに loadNextPageIfNeeded を呼んでも API は呼ばれない
        let callsBefore = await mock.searchCallCount
        model.loadNextPageIfNeeded()
        await waitTick(20)
        await #expect(mock.searchCallCount == callsBefore)
    }

    @Test func loadNextPage_failure_keepsExistingResults_andShowsRetry() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false)))
        model.query = "swift"
        await waitTick()

        await mock.setSearchResult(.failure(URLError(.notConnectedToInternet)))
        model.loadNextPageIfNeeded()
        await waitTick()

        guard case let .pagingError(state) = model.phase else {
            Issue.record("Expected pagingError phase")
            return
        }
        #expect(state.repositories.count == 30)
    }

    @Test func retryPaging_refetchesSamePage() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false)))
        model.query = "swift"
        await waitTick()

        await mock.setSearchResult(.failure(URLError(.notConnectedToInternet)))
        model.loadNextPageIfNeeded()
        await waitTick()

        let recoveryPage = makeRepos(count: 10, startId: 31)
        await mock.setSearchResult(.success(.init(repositories: recoveryPage, totalCount: 100, incompleteResults: false)))
        model.retryPaging()
        await waitTick()

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.repositories.count == 40)
        await #expect(mock.lastPage == 2)
    }

    @Test func newSearch_resetsPagination() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock) = makeSUT(searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false)))
        model.query = "swift"
        await waitTick()

        let newPage1 = makeRepos(count: 5, startId: 100)
        await mock.setSearchResult(.success(.init(repositories: newPage1, totalCount: 5, incompleteResults: false)))
        model.query = "rust"
        await waitTick()

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded phase")
            return
        }
        #expect(state.repositories.count == 5)
        await #expect(mock.lastPage == 1)
    }

    // MARK: - US-5: 異常系

    @Test func networkFailure_transitionsToErrorNetwork() async {
        let (model, _) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        await waitTick()
        #expect(model.phase == .errorNetwork)
    }

    @Test func rateLimit_429_transitionsToErrorRateLimited() async {
        let error = HttpClientError.httpError(
            statusCode: 429,
            data: Data(),
            headers: ["X-RateLimit-Reset": "1700000000"]
        )
        let (model, _) = makeSUT(searchResult: .failure(error))
        model.query = "swift"
        await waitTick()
        guard case let .errorRateLimited(resetDate) = model.phase else {
            Issue.record("Expected errorRateLimited, got \(model.phase)")
            return
        }
        #expect(resetDate == Date(timeIntervalSince1970: 1700000000))
    }

    @Test func rateLimit_403WithRemainingZero_transitionsToErrorRateLimited() async {
        let error = HttpClientError.httpError(
            statusCode: 403,
            data: Data(),
            headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"]
        )
        let (model, _) = makeSUT(searchResult: .failure(error))
        model.query = "swift"
        await waitTick()
        guard case .errorRateLimited = model.phase else {
            Issue.record("Expected errorRateLimited")
            return
        }
    }

    @Test func retry_refetchesWithSameCondition() async {
        let (model, mock) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        await waitTick()
        #expect(model.phase == .errorNetwork)

        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        model.retry()
        await waitTick()

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after retry")
            return
        }
        #expect(state.repositories == GitHubRepo.samples)
    }

    @Test func refiringSearch_dropsExistingError() async {
        let (model, mock) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        await waitTick()
        #expect(model.phase == .errorNetwork)

        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        model.query = "rust"
        // 即時 loading に
        #expect(model.phase == .loading)
        await waitTick()
        guard case .loaded = model.phase else {
            Issue.record("Expected loaded after re-search")
            return
        }
    }

    @Test func onDisappear_cancelsInflightTask() async {
        let (model, _) = makeSUT(debounceDuration: .seconds(10))
        model.query = "swift"
        model.onDisappear()
        await waitTick()
        #expect(model.phase == .loading) // キャンセル済みのまま loading 表示が残る (UI には反映しない)
    }
}
