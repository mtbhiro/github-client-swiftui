import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchModelCacheTests {

    // MARK: - Helpers

    private func makeSUT(
        searchResult: Result<RepositorySearchPageResult, Error>? = nil,
        clock: MutableClock? = nil,
        cache: RepositorySearchCache? = nil
    ) -> (
        model: RepositorySearchModel,
        mock: MockGithubRepoRepository,
        cache: RepositorySearchCache,
        clock: MutableClock
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
        let clk = clock ?? MutableClock()
        let c = cache ?? RepositorySearchCache(now: clk.now)
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: .milliseconds(0),
            conditionStore: store,
            cache: c
        )
        return (model, mock, c, clk)
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

    @Test func sameQuery_within60Seconds_doesNotCallApi_andSkipsLoading() async {
        let (model, mock, _, clock) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        let baseline = await mock.searchCallCount
        guard case let .loaded(initialState) = model.phase else {
            Issue.record("Expected loaded after initial fetch")
            return
        }

        clock.advance(seconds: 30)
        // 同一キーワードで再検索を発火 (query を一旦変えて戻す)
        model.query = "different"
        await waitForInflight(model)
        clock.advance(seconds: 1)
        model.query = "swift"
        // キャッシュ命中なら同期的に直接 .loaded に遷移し、loading を経由しない (AC-1.1)
        guard case let .loaded(hitState) = model.phase else {
            Issue.record("Expected loaded immediately (cache hit), got \(model.phase)")
            return
        }
        // 結果リストが直前の loaded と同一 (AC-1.2)
        #expect(hitState.repositories == initialState.repositories)
        // inFlight task は張られていない (キャッシュ命中ではない paging の Task が残らない)
        await waitForInflight(model)
        // API は呼ばれない: baseline は "swift" 初回 +1 = 2 のはずなので、命中後も baseline+1 ("different" の 1 回) だけ増えている
        let afterCalls = await mock.searchCallCount
        #expect(afterCalls == baseline + 1)
    }

    // MARK: - AC-2.1: 60 秒超で失効

    @Test func sameQuery_after60Seconds_refetchesFromApi() async {
        let (model, mock, _, clock) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        let baseline = await mock.searchCallCount

        clock.advance(seconds: 60.001)
        model.query = "different"
        await waitForInflight(model)
        model.query = "swift"
        // 失効しているので loading 経由で API が走る
        #expect(model.phase == .loading)
        await waitForInflight(model)
        let afterCalls = await mock.searchCallCount
        #expect(afterCalls == baseline + 2) // "different" + "swift" 再取得
    }

    // MARK: - AC-2.2: TTL 起算点は API レスポンス受信時刻

    @Test func ttl_isMeasuredFromResponseReceivedTime_notDispatchTime() async {
        // 発火時刻と受信時刻に 30s のギャップを作って、TTL がどちらを起点にしているかを区別する。
        // - dispatch から +89s 経過時点でも、受信から +59s なら命中する (received 起算)
        // - dispatch 起算なら +60s で失効してしまうので命中しない
        let result = RepositorySearchPageResult(
            repositories: makeRepos(count: 3),
            totalCount: 3,
            incompleteResults: false
        )
        let clock = MutableClock()
        let (model, mock, _, _) = makeSUT(clock: clock)
        await mock.setSearchAsyncHandler { @Sendable [clock] _, _, _, _ in
            // API 応答までに 30 秒経過したことにする
            await clock.advance(seconds: 30)
            return result
        }
        model.query = "swift"
        await waitForInflight(model)
        // ここで stored_at は dispatch + 30s。受信完了直後。
        let baseline = await mock.searchCallCount

        // 受信時刻から +59 秒 (dispatch 時刻からは +89 秒) → received 起算なら命中
        clock.advance(seconds: 59)
        // ハンドラを外して、命中時に API が走らないことを担保
        await mock.setSearchAsyncHandler(nil)
        model.query = "rust"
        await waitForInflight(model)
        model.query = "swift"
        guard case .loaded = model.phase else {
            Issue.record("Expected cache hit (loaded) at received+59s, got \(model.phase)")
            return
        }
        let afterCalls = await mock.searchCallCount
        #expect(afterCalls == baseline + 1) // rust だけ追加 API
    }

    // MARK: - US-3 / AC-3.1, AC-3.2, AC-3.4: ページングのキャッシュ

    @Test func paging_cacheHit_skipsPagingLoading_andAppendsImmediately() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 10, startId: 31)
        let (model, mock, cache, _) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 40, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)

        // page=2 を先にキャッシュに入れておく
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key2 = RepositorySearchCache.Key(q: qString, sort: .default, page: 2)
        cache.put(key2, value: .init(repositories: page2, totalCount: 40, incompleteResults: false))

        let baseline = await mock.searchCallCount
        // 残り API は呼ばせない (これが命中時に呼ばれないことを保証)
        await mock.setSearchResult(.failure(URLError(.cancelled)))
        model.loadNextPageIfNeeded()
        // キャッシュ命中時は pagingLoading を経由しないが、List の onAppear 連鎖を避けるため
        // 1 tick 遅延で applyPagingResult を実行する。発火直後は loaded のまま (state は変わらない)。
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

    // MARK: - AC-3.3: 次ページ未取得/失効時は通常のページングフロー

    @Test func paging_cacheMiss_goesThroughPagingLoading_andThenAppends() async {
        let page1 = makeRepos(count: 30, startId: 1)
        let page2 = makeRepos(count: 30, startId: 31)
        let (model, mock, _, _) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(state1) = model.phase else {
            Issue.record("Expected loaded after first fetch")
            return
        }

        // page=2 はキャッシュにない。ハンドラで「呼ばれた直後の phase が pagingLoading であること」を確認しながら page2 を返す。
        await mock.setSearchAsyncHandler { @Sendable _, _, _, p in
            #expect(p == 2)
            return RepositorySearchPageResult(repositories: page2, totalCount: 100, incompleteResults: false)
        }
        let baseline = await mock.searchCallCount
        model.loadNextPageIfNeeded()
        // 同期的にいったん pagingLoading に遷移する
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
        // AC-3.4: page=1 命中 + page=2 失効の混在ケース
        let page1 = makeRepos(count: 30, startId: 1)
        let (model, mock, cache, _) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false))
        )
        model.query = "swift"
        await waitForInflight(model)
        // page=1 のキャッシュは存在する。次に page=2 を取りに行く時にキャッシュ未登録 → API 発火
        let page2 = makeRepos(count: 30, startId: 31)
        await mock.setSearchResult(.success(.init(repositories: page2, totalCount: 100, incompleteResults: false)))

        let baseline = await mock.searchCallCount
        model.loadNextPageIfNeeded()
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baseline + 1) // page=2 は API 発火
        // page=2 もキャッシュに保存されたはず
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key2 = RepositorySearchCache.Key(q: qString, sort: .default, page: 2)
        #expect(cache.get(key2) != nil)
    }

    // MARK: - US-4 / AC-4.1, AC-4.2: ソート

    @Test func sortRoundtrip_within60Seconds_returnsFromCache() async {
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
        let (model, mock, _, _) = makeSUT(searchResult: .success(starsResult))
        model.query = "swift"
        await waitForInflight(model)

        // sort を updated に変更
        await mock.setSearchResult(.success(updatedResult))
        model.setSort(.init(key: .updated, order: .desc))
        await waitForInflight(model)
        guard case let .loaded(updatedState) = model.phase, updatedState.repositories == updatedResult.repositories else {
            Issue.record("Expected updated sort result")
            return
        }
        let baselineAfterUpdated = await mock.searchCallCount

        // sort を stars に戻す → キャッシュ命中で API 未発火、loading 経由なし
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
        let (model, mock, cache, _) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        await waitForInflight(model)
        #expect(model.phase == .errorNetwork)

        // 同条件のキーがキャッシュに入っていない
        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key) == nil)

        // 再試行で API が呼ばれる (キャッシュから埋まらない)
        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        let baseline = await mock.searchCallCount
        model.retry()
        await waitForInflight(model)
        let after = await mock.searchCallCount
        #expect(after == baseline + 1)
    }

    // MARK: - AC-5.2: no-results はキャッシュされる

    @Test func noResults_isCached_andReplayedImmediately() async {
        let (model, mock, _, _) = makeSUT(
            searchResult: .success(.init(repositories: [], totalCount: 0, incompleteResults: false))
        )
        model.query = "nonexistent"
        await waitForInflight(model)
        guard case .noResults = model.phase else {
            Issue.record("Expected noResults after first fetch")
            return
        }

        // 別キーワードで一度走らせる
        await mock.setSearchResult(.success(.init(repositories: GitHubRepo.samples, totalCount: 3, incompleteResults: false)))
        model.query = "swift"
        await waitForInflight(model)

        // nonexistent に戻したらキャッシュ命中で同期的に noResults に
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

    // MARK: - AC-5.3: キャンセルはキャッシュされない (handler 内で確実に cancel が効くようにする)

    @Test func cancelledRequest_isNotCached() async {
        // ハンドラ内でレスポンス前にキャンセル待ちをし、cancel が到達した時点で CancellationError を投げる。
        // これにより「cache.put が呼ばれる前に cancel が効いている」ことが明示的に検証できる。
        let (model, mock, cache, _) = makeSUT()
        await mock.setSearchAsyncHandler { @Sendable _, _, _, _ in
            // キャンセルされるまで黙って待つ
            while !Task.isCancelled {
                await Task.yield()
            }
            throw CancellationError()
        }
        model.query = "swift"
        // 1 tick 進めてハンドラに入らせる
        await Task.yield()
        await Task.yield()
        model.onDisappear() // cancel
        await waitForInflight(model)

        let qString = RepositorySearchQueryBuilder.build(keyword: "swift", qualifiers: .empty)
        let key = RepositorySearchCache.Key(q: qString, sort: .default, page: 1)
        #expect(cache.get(key) == nil)
    }

    // MARK: - AC-1.3: キャッシュ命中時に追加 UI 要素は出ない (Phase は通常の loaded と区別なし)

    @Test func cacheHit_phaseIsIndistinguishableFromNormalLoaded() async {
        let (model, _, _, _) = makeSUT()
        model.query = "swift"
        await waitForInflight(model)
        guard case let .loaded(first) = model.phase else {
            Issue.record("Expected loaded")
            return
        }

        model.query = "other"
        await waitForInflight(model)
        model.query = "swift"
        // 命中時の phase は通常の .loaded と区別がつかない
        guard case let .loaded(hit) = model.phase else {
            Issue.record("Expected loaded on cache hit")
            return
        }
        #expect(hit == first)
    }
}
