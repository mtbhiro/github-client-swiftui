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
}

@Observable
final class RepositorySearchModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            onQueryChanged()
        }
    }

    private(set) var phase: RepositorySearchPhase = .idle
    private(set) var appliedQualifiers: RepositorySearchQualifiers = .empty
    private(set) var sort: RepositorySearchSort = .default

    private static let perPage = 30
    private static let maxAccumulated = 1000

    private var currentTask: Task<Void, Never>?
    private let repository: GithubRepoRepositoryProtocol
    private let debounceDuration: Duration

    init(
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository(),
        debounceDuration: Duration = .milliseconds(300)
    ) {
        self.repository = repository
        self.debounceDuration = debounceDuration
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

    func applyQualifiers(_ qualifiers: RepositorySearchQualifiers) {
        guard qualifiers.isValid else { return }
        appliedQualifiers = qualifiers
        fireSearch(debounce: false)
    }

    func setSort(_ sort: RepositorySearchSort) {
        guard self.sort != sort else { return }
        self.sort = sort
        if hasActiveCondition {
            fireSearch(debounce: false)
        }
    }

    func removeChip(_ chip: RepositorySearchChip) {
        var q = appliedQualifiers
        switch chip {
        case .keyword:
            query = ""
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
        let sortKey = sort.key.rawValue
        let orderKey = sort.order.rawValue

        phase = .loading

        let repository = self.repository
        let debounceDuration = self.debounceDuration

        currentTask = Task { [weak self] in
            do {
                if debounce {
                    try await Task.sleep(for: debounceDuration)
                }
                let result = try await repository.searchRepositories(
                    query: qString,
                    sort: sortKey,
                    order: orderKey,
                    page: 1
                )
                guard let self else { return }
                if result.repositories.isEmpty {
                    self.phase = .noResults(query: trimmed)
                } else {
                    let capped = self.cap(result.repositories, currentCount: 0)
                    self.phase = .loaded(.init(
                        repositories: capped.list,
                        nextPage: 2,
                        hasMorePages: capped.list.count < Self.maxAccumulated
                            && result.repositories.count >= Self.perPage
                    ))
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                if let mapped = RepositorySearchErrorMapper.map(error) {
                    switch mapped {
                    case .network:
                        self.phase = .errorNetwork
                    case let .rateLimited(resetDate):
                        self.phase = .errorRateLimited(resetDate: resetDate)
                    }
                }
            }
        }
    }

    private func startPaging(from state: RepositorySearchLoadedState) {
        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let qString = RepositorySearchQueryBuilder.build(keyword: trimmed, qualifiers: appliedQualifiers)
        let sortKey = sort.key.rawValue
        let orderKey = sort.order.rawValue
        let nextPage = state.nextPage

        phase = .pagingLoading(state)

        let repository = self.repository

        currentTask = Task { [weak self] in
            do {
                let result = try await repository.searchRepositories(
                    query: qString,
                    sort: sortKey,
                    order: orderKey,
                    page: nextPage
                )
                guard let self else { return }
                let merged = state.repositories + result.repositories
                let capped = self.cap(merged, currentCount: 0)
                let reachedCap = capped.list.count >= Self.maxAccumulated
                let lastWasFull = result.repositories.count >= Self.perPage
                self.phase = .loaded(.init(
                    repositories: capped.list,
                    nextPage: nextPage + 1,
                    hasMorePages: !reachedCap && lastWasFull
                ))
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.phase = .pagingError(state)
            }
        }
    }

    private func cap(_ repos: [GitHubRepo], currentCount: Int) -> (list: [GitHubRepo], didCap: Bool) {
        if repos.count <= Self.maxAccumulated {
            return (repos, false)
        }
        return (Array(repos.prefix(Self.maxAccumulated)), true)
    }

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }
}
