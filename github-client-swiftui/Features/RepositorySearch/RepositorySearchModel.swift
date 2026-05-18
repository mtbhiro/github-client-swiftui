import Foundation
import Observation

struct RepositorySearchLoadedState: Sendable, Equatable {
    var repositories: [GitHubRepo]
    var nextPage: Int
    var hasMorePages: Bool
}

enum RepositorySearchPhase: Sendable, Equatable {
    case idle
    case loading
    case loaded(RepositorySearchLoadedState)
    case noResults(query: String)
    case errorNetwork
    case errorRateLimited(resetDate: Date?)
    case pagingLoading(RepositorySearchLoadedState)
    case pagingError(RepositorySearchLoadedState)

    /// List ベースで表示する phase からの状態抽出。View で switch case を分岐せず単一 List 上で
    /// 描画するために使う (スクロール位置維持のため)。
    struct ListPresentation {
        let state: RepositorySearchLoadedState
        let isPagingLoading: Bool
        let isPagingError: Bool
    }

    var listState: ListPresentation? {
        switch self {
        case let .loaded(state):
            return ListPresentation(state: state, isPagingLoading: false, isPagingError: false)
        case let .pagingLoading(state):
            return ListPresentation(state: state, isPagingLoading: true, isPagingError: false)
        case let .pagingError(state):
            return ListPresentation(state: state, isPagingLoading: false, isPagingError: true)
        case .idle, .loading, .noResults, .errorNetwork, .errorRateLimited:
            return nil
        }
    }
}

@Observable
final class RepositorySearchModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            guard !suppressQueryDidSet else { return }
            onQueryChanged()
        }
    }

    private var suppressQueryDidSet = false

    private(set) var phase: RepositorySearchPhase = .idle
    private(set) var appliedQualifiers: RepositorySearchQualifiers = .empty
    private(set) var sort: RepositorySearchSort = .default

    static let perPage = 30
    static let maxAccumulated = 1000

    var inFlightTask: Task<Void, Never>? { currentTask }

    private var currentTask: Task<Void, Never>?
    private let repository: GithubRepoRepositoryProtocol
    private let debounceDuration: Duration
    private let conditionStore: RepositorySearchConditionStore
    private let cache: RepositorySearchCache

    init(
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository(),
        debounceDuration: Duration = .milliseconds(300),
        conditionStore: RepositorySearchConditionStore = RepositorySearchConditionStore(),
        cache: RepositorySearchCache = RepositorySearchCache()
    ) {
        self.repository = repository
        self.debounceDuration = debounceDuration
        self.conditionStore = conditionStore
        self.cache = cache
        if let snapshot = conditionStore.load() {
            self.appliedQualifiers = snapshot.qualifiers
            self.sort = snapshot.sort
        }
    }

    var chips: [RepositorySearchChip] {
        RepositorySearchChipFormatter.chips(keyword: query, qualifiers: appliedQualifiers)
    }

    var hasActiveCondition: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !appliedQualifiers.isEmpty
    }

    // MARK: - User intents

    func onDisappear() {
        cancelCurrentTask()
    }

    func onSubmit() {
        fireSearch(debounce: false)
    }

    func retry() {
        fireSearch(debounce: false)
    }

    /// Pull-to-refresh: 現在の検索条件で page=1 を API から再取得する (PRD AC-6.1)。
    /// `.refreshable` から呼ばれるため async。
    /// 取得中は既存の `.loaded` を維持し、`.refreshable` 標準のスピナーだけが表示される。
    /// 成功時に限って page=1 以降のキャッシュを破棄し、新結果で `.loaded` を差し替える。
    /// 失敗時は既存リストとキャッシュをそのまま残す。
    func refresh() async {
        guard hasActiveCondition else { return }
        guard case .loaded = phase else { return }

        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let qString = RepositorySearchQueryBuilder.build(keyword: trimmed, qualifiers: appliedQualifiers)
        let sortKey = sort.key.rawValue
        let orderKey = sort.order.rawValue
        let snapshotSort = sort

        let task = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await self.repository.searchRepositories(
                    query: qString,
                    sort: sortKey,
                    order: orderKey,
                    page: 1
                )
                try Task.checkCancellation()
                self.cache.invalidate(q: qString, sort: snapshotSort)
                let key = RepositorySearchCache.Key(q: qString, sort: snapshotSort, page: 1)
                self.cache.put(key, value: result)
                self.applyInitialResult(result, query: trimmed)
            } catch is CancellationError {
                return
            } catch {
                // 失敗時は既存の .loaded（および対応キャッシュ）を維持する。
                // refresh は明示的なユーザー操作だが、エラーで画面全体を入れ替えると古い結果まで失われるため何もしない。
                return
            }
        }
        currentTask = task
        await task.value
    }

    func applyQualifiers(_ qualifiers: RepositorySearchQualifiers) {
        guard qualifiers.isValid else { return }
        appliedQualifiers = qualifiers
        persistConditionIfNeeded()
        fireSearch(debounce: false)
    }

    func setSort(_ sort: RepositorySearchSort) {
        guard self.sort != sort else { return }
        self.sort = sort
        persistConditionIfNeeded()
        if hasActiveCondition {
            fireSearch(debounce: false)
        }
    }

    func removeChip(_ chip: RepositorySearchChip) {
        if case .keyword = chip {
            // keyword 削除も他のチップ削除と同じく即時再検索する。
            // query の didSet 経由（debounce: true）と挙動を分けないため、
            // 一旦 didSet を抑止して値だけ更新し、明示的に fireSearch(debounce: false) を呼ぶ。
            setQueryWithoutFiring("")
            fireSearch(debounce: false)
            return
        }

        var q = appliedQualifiers
        switch chip {
        case .keyword:
            return
        case .inTargets:
            q.inTargets = []
        case .language:
            q.language = nil
        case .stars:
            q.stars = .init(min: nil, max: nil)
        case .pushed:
            q.pushed = .init(from: nil, to: nil)
        case let .topic(_, value):
            q.topics.removeAll { $0 == value }
        }
        appliedQualifiers = q
        persistConditionIfNeeded()
        fireSearch(debounce: false)
    }

    private func setQueryWithoutFiring(_ newValue: String) {
        suppressQueryDidSet = true
        query = newValue
        suppressQueryDidSet = false
    }

    // MARK: - Pagination

    func loadNextPageIfNeeded() {
        guard case let .loaded(state) = phase else { return }
        guard state.hasMorePages else { return }
        startPaging(from: state)
    }

    func retryPaging() {
        guard case let .pagingError(state) = phase else { return }
        startPaging(from: state)
    }

    // MARK: - Internals

    private func onQueryChanged() {
        fireSearch(debounce: true)
    }

    private func fireSearch(debounce: Bool) {
        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKeyword = !trimmed.isEmpty
        let hasQualifier = !appliedQualifiers.isEmpty
        guard hasKeyword || hasQualifier else {
            phase = .idle
            return
        }

        let qString = RepositorySearchQueryBuilder.build(keyword: trimmed, qualifiers: appliedQualifiers)
        let cacheKey = makeCacheKey(q: qString, page: 1)

        // PRD AC-1.1: キャッシュ命中時は loading を経由せず同期的に loaded/noResults に直接遷移する。
        if let cached = cache.get(cacheKey) {
            applyInitialResult(cached, query: trimmed)
            return
        }

        // debounce 中も loading 状態にして、前の結果が一瞬残るのを防ぐ。
        // ユーザー操作直後に常に「クリアされた loading 画面」が見える状態を作る。
        phase = .loading

        let sortKey = sort.key.rawValue
        let orderKey = sort.order.rawValue
        currentTask = Task { [weak self] in
            do {
                if debounce, let duration = self?.debounceDuration {
                    try await Task.sleep(for: duration)
                }
                guard let self else { return }
                let result = try await self.repository.searchRepositories(
                    query: qString,
                    sort: sortKey,
                    order: orderKey,
                    page: 1
                )
                try Task.checkCancellation()
                self.cache.put(cacheKey, value: result)
                self.applyInitialResult(result, query: trimmed)
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                switch RepositorySearchErrorMapper.map(error) {
                case .none:
                    return
                case .network?:
                    self.phase = .errorNetwork
                case let .rateLimited(resetDate)?:
                    self.phase = .errorRateLimited(resetDate: resetDate)
                }
            }
        }
    }

    private func applyInitialResult(_ result: RepositorySearchPageResult, query trimmed: String) {
        if result.repositories.isEmpty {
            phase = .noResults(query: trimmed)
        } else {
            let capped = Self.cap(existing: [], appending: result.repositories)
            phase = .loaded(.init(
                repositories: capped.list,
                nextPage: 2,
                hasMorePages: Self.shouldKeepPaging(
                    reachedCap: capped.reachedCap,
                    lastPageCount: result.repositories.count
                )
            ))
        }
    }

    private func startPaging(from state: RepositorySearchLoadedState) {
        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let qString = RepositorySearchQueryBuilder.build(keyword: trimmed, qualifiers: appliedQualifiers)
        let nextPage = state.nextPage
        let cacheKey = makeCacheKey(q: qString, page: nextPage)

        // PRD AC-3.2: 次ページがキャッシュ命中なら paging-loading を経由せず loaded のまま末尾に追記する。
        if let cached = cache.get(cacheKey) {
            applyPagingResult(cached, base: state, nextPage: nextPage)
            return
        }

        phase = .pagingLoading(state)

        let sortKey = sort.key.rawValue
        let orderKey = sort.order.rawValue
        currentTask = Task { [weak self] in
            do {
                guard let self else { return }
                let result = try await self.repository.searchRepositories(
                    query: qString,
                    sort: sortKey,
                    order: orderKey,
                    page: nextPage
                )
                try Task.checkCancellation()
                self.cache.put(cacheKey, value: result)
                self.applyPagingResult(result, base: state, nextPage: nextPage)
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.phase = .pagingError(state)
            }
        }
    }

    private func applyPagingResult(
        _ result: RepositorySearchPageResult,
        base state: RepositorySearchLoadedState,
        nextPage: Int
    ) {
        let capped = Self.cap(existing: state.repositories, appending: result.repositories)
        phase = .loaded(.init(
            repositories: capped.list,
            nextPage: nextPage + 1,
            hasMorePages: Self.shouldKeepPaging(
                reachedCap: capped.reachedCap,
                lastPageCount: result.repositories.count
            )
        ))
    }

    private static func cap(
        existing: [GitHubRepo],
        appending: [GitHubRepo]
    ) -> (list: [GitHubRepo], reachedCap: Bool) {
        let merged = existing + appending
        if merged.count >= maxAccumulated {
            return (Array(merged.prefix(maxAccumulated)), true)
        }
        return (merged, false)
    }

    private static func shouldKeepPaging(reachedCap: Bool, lastPageCount: Int) -> Bool {
        // 1000 件 cap に達した時点で、それ以上のページング要求は発生させない (AC-4.4)。
        // それ未満でも、最後のレスポンスが per_page 未満なら次ページは存在しないと判断する。
        !reachedCap && lastPageCount >= perPage
    }

    private func makeCacheKey(q: String, page: Int) -> RepositorySearchCache.Key {
        RepositorySearchCache.Key(q: q, sort: sort, page: page)
    }

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func persistConditionIfNeeded() {
        if appliedQualifiers.isEmpty && sort == .default {
            conditionStore.clear()
        } else {
            conditionStore.save(
                RepositorySearchConditionSnapshot(qualifiers: appliedQualifiers, sort: sort)
            )
        }
    }
}
