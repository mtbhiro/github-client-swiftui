import Foundation
import Observation

struct LoadedRepositories: Sendable, Equatable {
    let query: String
    var repositories: [GitHubRepo]
    var currentPage: Int
    var hasMorePages: Bool
    var isLoadingMore: Bool = false
}

enum RepositorySearchPhase: Sendable, Equatable {
    case idle
    case loading
    case loaded(LoadedRepositories)
    case error(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
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

    private static let perPage = 30
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

    func onDisappear() {
        cancelCurrentTask()
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
        cancelCurrentTask()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let results = try await repository.searchRepositories(query: trimmed, page: 1)
            phase = .loaded(LoadedRepositories(
                query: trimmed,
                repositories: results,
                currentPage: 1,
                hasMorePages: results.count >= Self.perPage
            ))
        } catch is CancellationError {
        } catch {
            phase = .error(message: error.localizedDescription)
        }
    }

    func loadNextPageIfNeeded() {
        guard case var .loaded(state) = phase, state.hasMorePages, !state.isLoadingMore else { return }

        let query = state.query
        let nextPage = state.currentPage + 1

        state.isLoadingMore = true
        phase = .loaded(state)

        currentTask = Task { [weak self] in
            do {
                let results = try await self?.repository.searchRepositories(query: query, page: nextPage) ?? []
                guard let self, case let .loaded(state) = self.phase else { return }
                self.phase = .loaded(LoadedRepositories(
                    query: state.query,
                    repositories: state.repositories + results,
                    currentPage: nextPage,
                    hasMorePages: results.count >= Self.perPage
                ))
            } catch is CancellationError {
            } catch {
                guard let self, case var .loaded(state) = self.phase else { return }
                state.isLoadingMore = false
                self.phase = .loaded(state)
            }
        }
    }

    private func onQueryChanged() {
        startSearch(debounce: true)
    }

    private func startSearch(debounce: Bool) {
        cancelCurrentTask()

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
        if case let .loaded(state) = phase, state.query == query { return }
        phase = .loading
        executeSearch(query: query, debounce: false)
    }

    private func startDebouncedSearch(query: String) {
        if !phase.isLoaded {
            phase = .loading
        }
        executeSearch(query: query, debounce: true)
    }

    private func executeSearch(query: String, debounce: Bool) {
        let duration = debounceDuration
        currentTask = Task { [weak self] in
            do {
                if debounce {
                    try await Task.sleep(for: duration)
                    guard let self else { return }
                    self.phase = .loading
                } else {
                    guard self != nil else { return }
                }
                let results = try await self?.repository.searchRepositories(query: query, page: 1) ?? []
                guard let self else { return }
                self.phase = .loaded(LoadedRepositories(
                    query: query,
                    repositories: results,
                    currentPage: 1,
                    hasMorePages: results.count >= Self.perPage
                ))
            } catch is CancellationError {
            } catch {
                guard let self else { return }
                self.phase = .error(message: error.localizedDescription)
            }
        }
    }

    private func resetToIdle() {
        phase = .idle
    }

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

}
