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

    private var searchTask: Task<Void, Never>?
    private var lastSearchedQuery: String = ""
    private let repository: RepositorySearchRepositoryProtocol
    private let debounceDuration: Duration

    init(
        repository: RepositorySearchRepositoryProtocol = RepositorySearchRepository(),
        debounceDuration: Duration = .milliseconds(300)
    ) {
        self.repository = repository
        self.debounceDuration = debounceDuration
    }

    func onAppear() {}

    func onDisappear() {
        cancelSearch()
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

    private func onQueryChanged() {
        startSearch(debounce: true)
    }

    private func startSearch(debounce: Bool) {
        cancelSearch()

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
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

}
