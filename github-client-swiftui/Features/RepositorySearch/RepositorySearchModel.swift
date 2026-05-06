import Foundation
import Observation

enum RepositorySearchPhase: Sendable {
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
            onQueryChanged(oldValue: oldValue, newValue: query)
        }
    }

    private(set) var phase: RepositorySearchPhase = .idle

    private var searchTask: Task<Void, Never>?

    private let debounceDuration: Duration = .milliseconds(300)
    private let fakeLoadDuration: Duration = .seconds(1)

    func onAppear() {
        print("[RepositorySearchModel] onAppear")
    }

    func onDisappear() {
        print("[RepositorySearchModel] onDisappear — cancel pending tasks")
        cancelSearch()
    }

    func onSubmit() {
        print("[RepositorySearchModel] onSubmit query=\(query)")
        startSearch(debounce: false)
    }

    func clearQuery() {
        print("[RepositorySearchModel] clearQuery")
        query = ""
    }

    func retry() {
        print("[RepositorySearchModel] retry query=\(query)")
        startSearch(debounce: false)
    }

    private func onQueryChanged(oldValue: String, newValue: String) {
        print("[RepositorySearchModel] queryChanged old=\"\(oldValue)\" new=\"\(newValue)\" — debounce reset")
        startSearch(debounce: true)
    }

    private func startSearch(debounce: Bool) {
        cancelSearch()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }

        phase = .loading

        let debounceDuration = debounceDuration
        let fakeLoadDuration = fakeLoadDuration

        searchTask = Task { [weak self] in
            do {
                if debounce {
                    try await Task.sleep(for: debounceDuration)
                }
                try await Task.sleep(for: fakeLoadDuration)
                try Task.checkCancellation()
            } catch is CancellationError {
                print("[RepositorySearchModel] search cancelled query=\"\(trimmed)\"")
                return
            } catch {
                print("[RepositorySearchModel] search sleep error=\(error)")
                return
            }

            guard let self else { return }
            print("[RepositorySearchModel] search finished query=\"\(trimmed)\"")
            self.phase = .loaded(isEmpty: false)
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
}
