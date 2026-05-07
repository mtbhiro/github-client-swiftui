import Foundation
import Observation

enum RepositorySearchPhase: Sendable, Equatable {
    case idle
    case loading
    case loaded(isEmpty: Bool)
    case error(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

@MainActor
@Observable
final class RepositorySearchModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            onQueryChanged()
        }
    }

    private(set) var phase: RepositorySearchPhase = .idle
    private(set) var repositories: [GitHubRepo] = []
    private(set) var isLoadingMore: Bool = false
    private(set) var hasMorePages: Bool = false

    private static let perPage = 30
    private var currentPage: Int = 1
    private var searchTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var lastSearchedQuery: String = ""
    private let repository: GithubRepoRepositoryProtocol
    private let debounceDuration: Duration

    init(
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository(),
        debounceDuration: Duration = .milliseconds(300)
    ) {
        self.repository = repository
        self.debounceDuration = debounceDuration
    }

    func onAppear() {}

    func onDisappear() {
        cancelSearch()
        cancelLoadMore()
    }

    func onSubmit() {
        startSearch(debounce: false)
    }

    func clearQuery() {
        query = ""
    }

    func retry() {
        startSearch(debounce: false)
    }

    func refresh() async {
        cancelSearch()
        cancelLoadMore()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let results = try await repository.searchRepositories(query: trimmed, page: 1)
            repositories = results
            currentPage = 1
            hasMorePages = results.count >= Self.perPage
            lastSearchedQuery = trimmed
            phase = .loaded(isEmpty: results.isEmpty)
        } catch is CancellationError {
        } catch {
            phase = .error(message: error.localizedDescription)
        }
    }

    func loadNextPageIfNeeded() {
        guard hasMorePages, !isLoadingMore, phase.isLoaded else { return }

        let query = lastSearchedQuery
        let nextPage = currentPage + 1

        isLoadingMore = true
        loadMoreTask = Task { [weak self] in
            do {
                let results = try await self?.repository.searchRepositories(query: query, page: nextPage) ?? []
                try Task.checkCancellation()
                guard let self else { return }
                self.repositories.append(contentsOf: results)
                self.currentPage = nextPage
                self.hasMorePages = results.count >= Self.perPage
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
            }
            self?.isLoadingMore = false
        }
    }

    private func onQueryChanged() {
        startSearch(debounce: true)
    }

    private func startSearch(debounce: Bool) {
        cancelSearch()
        cancelLoadMore()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetToIdle()
            return
        }

        if debounce {
            startDebouncedSearch(query: trimmed)
        } else {
            startImmediateSearch(query: trimmed)
        }
    }

    private func startImmediateSearch(query: String) {
        guard query != lastSearchedQuery || !phase.isLoaded else { return }
        phase = .loading
        executeSearch(query: query, debounce: false)
    }

    private func startDebouncedSearch(query: String) {
        if repositories.isEmpty {
            phase = .loading
        }
        executeSearch(query: query, debounce: true)
    }

    private func executeSearch(query: String, debounce: Bool) {
        let duration = debounceDuration
        searchTask = Task { [weak self] in
            do {
                if debounce {
                    try await Task.sleep(for: duration)
                    guard let self else { return }
                    self.phase = .loading
                } else {
                    guard self != nil else { return }
                }
                let results = try await self?.repository.searchRepositories(query: query, page: 1) ?? []
                try Task.checkCancellation()
                guard let self else { return }
                self.repositories = results
                self.currentPage = 1
                self.hasMorePages = results.count >= Self.perPage
                self.lastSearchedQuery = query
                self.phase = .loaded(isEmpty: results.isEmpty)
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .error(message: error.localizedDescription)
            }
        }
    }

    private func resetToIdle() {
        phase = .idle
        repositories = []
        lastSearchedQuery = ""
        currentPage = 1
        hasMorePages = false
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

    private func cancelLoadMore() {
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
    }

}
