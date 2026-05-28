import Foundation
import Observation

@Observable
final class RepositorySearchModel {

    struct LoadedState: Sendable, Equatable {
        var repositories: [GitHubRepo]
        var nextPage: Int
        var hasMorePages: Bool
    }

    struct ListPresentation {
        let state: LoadedState
        let isPagingLoading: Bool
        let isPagingError: Bool
    }

    enum Phase: Sendable, Equatable {
        case idle
        case loading
        case loaded(LoadedState)
        case noResults(query: String)
        case errorNetwork
        case errorRateLimited(resetDate: Date?)
        case pagingLoading(LoadedState)
        case pagingError(LoadedState)
    }

    var query: String = ""

    private(set) var phase: Phase = .idle
    private(set) var appliedQualifiers: RepositorySearchQualifiers = .empty
    private(set) var sort: RepositorySearchSort = .default

    static let perPage = PaginationConstants.itemsPerPage
    static let maxAccumulated = 1000

    var inFlightTask: Task<Void, Never>? { currentTask }

    private var currentTask: Task<Void, Never>?
    private let repository: GithubRepoRepositoryProtocol
    private let debounceDuration: Duration
    private let conditionStore: RepositorySearchConditionStore
    private let cache: RepositorySearchCache

    init(
        repository: GithubRepoRepositoryProtocol,
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
                    query: qString, sort: sortKey, order: orderKey, page: 1
                )
                try Task.checkCancellation()
                self.cache.invalidate(query: qString, sort: snapshotSort)
                let key = RepositorySearchCache.Key(query: qString, sort: snapshotSort, page: 1)
                self.cache.put(key, value: result)
                self.applyInitialResult(result, query: trimmed)
            } catch is CancellationError {
                return
            } catch {
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
            query = ""
            fireSearch(debounce: false)
            return
        }

        var qualifiers = appliedQualifiers
        switch chip {
        case .keyword:
            return
        case .inTargets:
            qualifiers.inTargets = []
        case .language:
            qualifiers.language = nil
        case .stars:
            qualifiers.stars = .init(min: nil, max: nil)
        case .pushed:
            qualifiers.pushed = .init(from: nil, to: nil)
        case let .topic(_, value):
            qualifiers.topics.removeAll { $0 == value }
        }
        appliedQualifiers = qualifiers
        persistConditionIfNeeded()
        fireSearch(debounce: false)
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

    func onQueryChanged() {
        fireSearch(debounce: true)
    }

    func setQuery(_ newValue: String) {
        guard query != newValue else { return }
        query = newValue
        onQueryChanged()
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
        let cacheKey = makeCacheKey(query: qString, page: 1)

        if let cached = cache.get(cacheKey) {
            applyInitialResult(cached, query: trimmed)
            return
        }

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
                    query: qString, sort: sortKey, order: orderKey, page: 1
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
                    reachedCap: capped.reachedCap, lastPageCount: result.repositories.count
                )
            ))
        }
    }

    private func startPaging(from state: LoadedState) {
        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let qString = RepositorySearchQueryBuilder.build(keyword: trimmed, qualifiers: appliedQualifiers)
        let nextPage = state.nextPage
        let cacheKey = makeCacheKey(query: qString, page: nextPage)

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
                    query: qString, sort: sortKey, order: orderKey, page: nextPage
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
        _ result: RepositorySearchPageResult, base state: LoadedState, nextPage: Int
    ) {
        let capped = Self.cap(existing: state.repositories, appending: result.repositories)
        phase = .loaded(.init(
            repositories: capped.list,
            nextPage: nextPage + 1,
            hasMorePages: Self.shouldKeepPaging(
                reachedCap: capped.reachedCap, lastPageCount: result.repositories.count
            )
        ))
    }

    private static func cap(
        existing: [GitHubRepo], appending: [GitHubRepo]
    ) -> (list: [GitHubRepo], reachedCap: Bool) {
        let merged = existing + appending
        if merged.count >= maxAccumulated {
            return (Array(merged.prefix(maxAccumulated)), true)
        }
        return (merged, false)
    }

    private static func shouldKeepPaging(reachedCap: Bool, lastPageCount: Int) -> Bool {
        !reachedCap && lastPageCount >= perPage
    }

    private func makeCacheKey(query: String, page: Int) -> RepositorySearchCache.Key {
        RepositorySearchCache.Key(query: query, sort: sort, page: page)
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

extension RepositorySearchModel.Phase {
    var listState: RepositorySearchModel.ListPresentation? {
        switch self {
        case let .loaded(state):
            RepositorySearchModel.ListPresentation(state: state, isPagingLoading: false, isPagingError: false)
        case let .pagingLoading(state):
            RepositorySearchModel.ListPresentation(state: state, isPagingLoading: true, isPagingError: false)
        case let .pagingError(state):
            RepositorySearchModel.ListPresentation(state: state, isPagingLoading: false, isPagingError: true)
        case .idle, .loading, .noResults, .errorNetwork, .errorRateLimited:
            nil
        }
    }
}
