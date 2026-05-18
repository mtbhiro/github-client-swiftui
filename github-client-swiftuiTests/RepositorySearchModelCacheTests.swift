import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchModelCacheTests {

    // MARK: - Helpers

    private func makeSUT(
        searchResult: Result<RepositorySearchPageResult, Error>? = nil,
        cache: RepositorySearchCache? = nil
    ) -> (
        model: RepositorySearchModel,
        mock: MockGithubRepoRepository,
        cache: RepositorySearchCache
    ) {
        let mock = MockGithubRepoRepository(
            searchResult: searchResult ?? .success(.init(
                repositories: GitHubRepo.samples,
                totalCount: GitHubRepo.samples.count,
                incompleteResults: false
            ))
        )
        let suiteName = "RepositorySearchModelCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = RepositorySearchConditionStore(defaults: defaults)
        let c = cache ?? RepositorySearchCache()
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: .milliseconds(0),
            conditionStore: store,
            cache: c
        )
        return (model, mock, c)
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

    private func waitForInflight(_ model: RepositorySearchModel) async {
        await model.inFlightTask?.value
    }

    // MARK: - US-1 / AC-1.1, AC-1.2, AC-1.3

    @Test func sameQuery_doesNotCallApi_andSkipsLoading() async {
        let (model, mock, _) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        let baseline = await mock.searchCallCount
        guard case let .loaded(initialState) = model.phase else {
            Issue.record("Expected loaded after initial fetch")
            return
        }

        model.query = "different"
        await waitForInflight(model)
        model.query = "swift"
        // キャッシュ命中なら同期的に直接 .loaded に遷移し、loading を経由しない (AC-1.1)
        guard case let .loaded(hitState) = model.phase else {
            Issue.record("Expected loaded immediately (cache hit), got \(model.phase)")
            return
        }
        // 結果リストが直前の loaded と同一 (AC-1.2)
        #expect(hitState.repositories == initialState.repositories)
        await waitForInflight(model)
        // API は "swift" 初回 + "different" だけ。命中後は増えない
        let afterCalls = await mock.searchCallCount
        #expect(afterCalls == baseline + 1)
    }

    // MARK: - US-2 / AC-2.1: q1 -> q2 -> q1 の往復で q1 がキャッシュから即返し

    @Test func roundtripQuery_returnsFirstFromCache_withoutRefetching() async {
        let (model, mock, _) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        let baselineAfterSwift = await mock.searchCallCount

        model.query = "swifty"
        await waitForInflight(model)
        let baselineAfterSwifty = await mock.searchCallCount
        #expect(baselineAfterSwifty == baselineAfterSwift + 1)

        model.query = "swift"
        guard case .loaded = model.phase else {
            Issue.record("Expected loaded immediately on roundtrip, got \(model.phase)")
            return
        }
        await waitForInflight(model)
        let afterCalls = await mock.searchCallCount
        // swift 再取得は不要 (キャッシュ命中)
        #expect(afterCalls == baselineAfterSwifty)
    }

    // MARK: - US-3 / AC-3.1, AC-3.2, AC-3.4: ページングのキャッシュ

    @Test func paging_cacheHit_skipsPagingLoading_andAppendsImmediately() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 10, startId: 31)
        let (model, mock, cache) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 40, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)

        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key2 = RepositorySearchCache.Key(q: qString, sort: .default, page: 2)
        cache.put(key2, value: .init(repositories: page2, totalCount: 40, incompleteResults: false))

        let baseline = await mock.searchCallCount
        await mock.setSearchResult(.failure(URLError(.cancelled)))
        model.loadNextPageIfNeeded()
        // 命中時は pagingLoading を経由しない
        if case .pagingLoading = model.phase {
            Issue.record("Expected to stay loaded (no pagingLoading) on cache hit, got \(model.phase)")
            return
        }
        await waitForInflight(model)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after paging cache hit, got \(model.phase)")
            return
        }
        #expect(state.repositories.count == 40)
        let after = await mock.searchCallCount
        #expect(after == baseline)
    }

    // MARK: - AC-3.3: 次ページ未登録時は通常のページングフロー

    @Test func paging_cacheMiss_goesThroughPagingLoading_andThenAppends() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 30, startId: 31)
        let (model, mock, _) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(state1) = model.phase else {
            Issue.record("Expected loaded after first fetch")
            return
        }

        await mock.setSearchAsyncHandler { @Sendable _, _, _, p in
            #expect(p == 2)
            return RepositorySearchPageResult(repositories: page2, totalCount: 100, incompleteResults: false)
        }
        let baseline = await mock.searchCallCount
        model.loadNextPageIfNeeded()
        guard case let .pagingLoading(loadingState) = model.phase else {
            Issue.record("Expected pagingLoading on cache miss, got \(model.phase)")
            return
        }
        #expect(loadingState.repositories == state1.repositories)
        await waitForInflight(model)
        guard case let .loaded(after) = model.phase else {
            Issue.record("Expected loaded after paging, got \(model.phase)")
            return
        }
        #expect(after.repositories.count == 60)
        let afterCalls = await mock.searchCallCount
        #expect(afterCalls == baseline + 1)
    }

    @Test func paging_page1Hit_page2Miss_handlesEachIndependently() async {
        // AC-3.4
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock, cache) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)
        let page2 = makeRepos(count: 30, startId: 31)
        await mock.setSearchResult(.success(.init(repositories: page2, totalCount: 100, incompleteResults: false)))

        let baseline = await mock.searchCallCount
        model.loadNextPageIfNeeded()
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baseline + 1)
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key2 = RepositorySearchCache.Key(q: qString, sort: .default, page: 2)
        #expect(cache.get(key2) != nil)
    }

    // MARK: - US-4 / AC-4.1, AC-4.2: ソート

    @Test func sortRoundtrip_returnsFromCache() async {
        let starsResult = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 1),
            totalCount: 5,
            incompleteResults: false
        )
        let updatedResult = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 100),
            totalCount: 5,
            incompleteResults: false
        )
        let (model, mock, _) = makeSUT(searchResult: .success(starsResult))
        model.query = "swift"
        await waitForInflight(model)

        await mock.setSearchResult(.success(updatedResult))
        model.setSort(.init(key: .updated, order: .desc))
        await waitForInflight(model)
        guard case let .loaded(updatedState) = model.phase, updatedState.repositories == updatedResult.repositories else {
            Issue.record("Expected updated sort result")
            return
        }
        let baselineAfterUpdated = await mock.searchCallCount

        model.setSort(.default)
        guard case let .loaded(roundtripState) = model.phase else {
            Issue.record("Expected loaded immediately on sort roundtrip (cache hit), got \(model.phase)")
            return
        }
        #expect(roundtripState.repositories == starsResult.repositories)
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baselineAfterUpdated)
    }

    // MARK: - US-5 / AC-5.1: error はキャッシュされない

    @Test func errorResults_areNotCached() async {
        let (model, mock, cache) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        await waitForInflight(model)
        #expect(model.phase == .errorNetwork)

        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key) == nil)

        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        let baseline = await mock.searchCallCount
        model.retry()
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baseline + 1)
    }

    // MARK: - AC-5.2: no-results はキャッシュされる

    @Test func noResults_isCached_andReplayedImmediately() async {
        let (model, mock, _) = makeSUT(
            searchResult: .success(.init(repositories: [], totalCount: 0, incompleteResults: false))
        )
        model.query = "nonexistent"
        await waitForInflight(model)
        guard case .noResults = model.phase else {
            Issue.record("Expected noResults after first fetch")
            return
        }

        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        model.query = "swift"
        await waitForInflight(model)

        let baseline = await mock.searchCallCount
        model.query = "nonexistent"
        guard case let .noResults(q) = model.phase else {
            Issue.record("Expected noResults immediately on cache hit, got \(model.phase)")
            return
        }
        #expect(q == "nonexistent")
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baseline)
    }

    // MARK: - AC-5.3: キャンセルはキャッシュされない

    @Test func cancelledRequest_isNotCached() async {
        let (model, mock, cache) = makeSUT()
        await mock.setSearchAsyncHandler { @Sendable _, _, _, _ in
            while !Task.isCancelled {
                await Task.yield()
            }
            throw CancellationError()
        }
        model.query = "swift"
        await Task.yield()
        await Task.yield()
        model.onDisappear()
        await waitForInflight(model)

        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key) == nil)
    }

    // MARK: - AC-1.3: キャッシュ命中時の phase は通常の loaded と区別なし

    @Test func cacheHit_phaseIsIndistinguishableFromNormalLoaded() async {
        let (model, _, _) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(first) = model.phase else {
            Issue.record("Expected loaded")
            return
        }

        model.query = "other"
        await waitForInflight(model)
        model.query = "swift"
        guard case let .loaded(hit) = model.phase else {
            Issue.record("Expected loaded on cache hit")
            return
        }
        #expect(hit == first)
    }

    // MARK: - US-6 / AC-6.1, AC-6.2: Pull-to-refresh

    @Test func refresh_invalidatesCurrentConditionCache_andRefetchesFromApi() async {
        let initial = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 1),
            totalCount: 5,
            incompleteResults: false
        )
        let refreshed = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 100),
            totalCount: 5,
            incompleteResults: false
        )
        let (model, mock, cache) = makeSUT(searchResult: .success(initial))
        model.query = "swift"
        await waitForInflight(model)

        // 同条件で再検索しても cache 命中なので API は増えない
        let baselineBeforeRefresh = await mock.searchCallCount

        // refresh で page=1 を捨てて新しいレスポンスを取りに行く
        await mock.setSearchResult(.success(refreshed))
        await model.refresh()

        let afterRefresh = await mock.searchCallCount
        #expect(afterRefresh == baselineBeforeRefresh + 1)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after refresh, got \(model.phase)")
            return
        }
        #expect(state.repositories == refreshed.repositories)

        // 新しい結果がキャッシュに登録されている
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key1 = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key1)?.repositories == refreshed.repositories)
    }

    // AC-6.1: refresh 中も既存の .loaded を維持し、.loading に落ちない
    @Test func refresh_keepsLoadedState_whileFetching() async {
        let initial = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 1),
            totalCount: 5,
            incompleteResults: false
        )
        let refreshed = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 100),
            totalCount: 5,
            incompleteResults: false
        )
        let (model, mock, _) = makeSUT(searchResult: .success(initial))
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(initialState) = model.phase else {
            Issue.record("Expected loaded after initial fetch")
            return
        }

        // refresh の API レスポンスを意図的に遅延させ、その間 phase を観測する。
        await mock.setSearchAsyncHandler { @Sendable _, _, _, _ in
            // 1 hop だけ待たせて、refresh() 呼び出し直後の phase を観測できるようにする。
            await Task.yield()
            await Task.yield()
            return refreshed
        }

        async let refreshFinished: Void = model.refresh()
        // refresh 開始直後は handler 内で suspend しているはずなので、
        // 既存の .loaded がそのまま見えていることを確認する。
        await Task.yield()
        guard case let .loaded(midState) = model.phase else {
            Issue.record("Expected to stay loaded during refresh, got \(model.phase)")
            return
        }
        #expect(midState.repositories == initialState.repositories)
        await refreshFinished

        guard case let .loaded(after) = model.phase else {
            Issue.record("Expected loaded after refresh, got \(model.phase)")
            return
        }
        #expect(after.repositories == refreshed.repositories)
    }

    // AC-6.3: refresh が失敗したとき、既存の .loaded と既存キャッシュが維持される
    @Test func refresh_failure_keepsExistingListAndCache() async {
        let initial = RepositorySearchPageResult(
            repositories: makeRepos(count: 5, startId: 1),
            totalCount: 5,
            incompleteResults: false
        )
        let (model, mock, cache) = makeSUT(searchResult: .success(initial))
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(initialState) = model.phase else {
            Issue.record("Expected loaded after initial fetch")
            return
        }
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key1 = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key1)?.repositories == initial.repositories)

        await mock.setSearchResult(.failure(URLError(.notConnectedToInternet)))
        await model.refresh()

        // 既存の .loaded がそのまま残ること
        guard case let .loaded(after) = model.phase else {
            Issue.record("Expected loaded to be preserved on refresh failure, got \(model.phase)")
            return
        }
        #expect(after.repositories == initialState.repositories)

        // 既存キャッシュも破棄されていないこと
        #expect(cache.get(key1)?.repositories == initial.repositories)
    }

    @Test func refresh_dropsAllPagesForCurrentCondition_keepingOtherEntries() {
        let cache = RepositorySearchCache()
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key1 = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        let key2 = RepositorySearchCache.Key(q: qString, sort: .default, page: 2)
        let otherQ = RepositorySearchCache.Key(q: "other", sort: .default, page: 1)
        let dummy = RepositorySearchPageResult(repositories: [], totalCount: 0, incompleteResults: false)
        cache.put(key1, value: dummy)
        cache.put(key2, value: dummy)
        cache.put(otherQ, value: dummy)

        cache.invalidate(q: qString, sort: .default)

        #expect(cache.get(key1) == nil)
        #expect(cache.get(key2) == nil)
        #expect(cache.get(otherQ) != nil)
    }
}
