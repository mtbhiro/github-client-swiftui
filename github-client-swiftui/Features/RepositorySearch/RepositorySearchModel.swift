import Foundation
import Observation

enum RepositorySearchPhase: Sendable, Equatable {
    case idle
    case loading
    case loaded(isEmpty: Bool)
    case error(message: String)
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
            phase = .idle
            repositories = []
            return
        }

        phase = .loading

        let debounceDuration = debounceDuration
        let repo = repository

        searchTask = Task { [weak self] in
            do {
                if debounce {
                    try await Task.sleep(for: debounceDuration)
                }
                let results = try await repo.searchRepositories(query: trimmed, page: 1)
                try Task.checkCancellation()
                guard let self else { return }
                self.repositories = results
                self.phase = .loaded(isEmpty: results.isEmpty)
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                guard !Task.isCancelled else { return }
                self.phase = .error(message: error.localizedDescription)
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }

}
