import Foundation
import Observation

struct LoadedIssues: Sendable, Equatable {
    var issues: [GitHubIssue]
    var currentPage: Int
    var hasMorePages: Bool
    var isLoadingMore: Bool = false
}

enum IssueListPhase: Sendable, Equatable {
    case loading
    case loaded(LoadedIssues)
    case error(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

@Observable
final class IssueListModel {
    private(set) var phase: IssueListPhase = .loading

    let fullName: GitHubRepoFullName

    private static let perPage = 30
    private var currentTask: Task<Void, Never>?
    private let repository: GithubRepoRepositoryProtocol

    init(
        fullName: GitHubRepoFullName,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        self.fullName = fullName
        self.repository = repository
    }

    func onAppear() {
        guard case .loading = phase, currentTask == nil else { return }
        load()
    }

    func onDisappear() {
        cancelCurrentTask()
    }

    func retry() {
        phase = .loading
        load()
    }

    func refresh() async {
        cancelCurrentTask()

        do {
            let results = try await repository.fetchIssues(fullName: fullName, page: 1)
            phase = .loaded(LoadedIssues(
                issues: results,
                currentPage: 1,
                hasMorePages: results.count >= Self.perPage
            ))
        } catch is CancellationError {
        } catch {
            phase = .error(message: "Issue の取得に失敗しました")
        }
    }

    func loadNextPageIfNeeded() {
        guard case var .loaded(state) = phase, state.hasMorePages, !state.isLoadingMore else { return }

        let nextPage = state.currentPage + 1

        state.isLoadingMore = true
        phase = .loaded(state)

        currentTask = Task { [weak self] in
            do {
                guard let self else { return }
                let results = try await self.repository.fetchIssues(fullName: self.fullName, page: nextPage)
                guard case let .loaded(state) = self.phase else { return }
                self.phase = .loaded(LoadedIssues(
                    issues: state.issues + results,
                    currentPage: nextPage,
                    hasMorePages: results.count >= Self.perPage
                ))
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled, case var .loaded(state) = self.phase else { return }
                state.isLoadingMore = false
                self.phase = .loaded(state)
            }
        }
    }

    private func load() {
        cancelCurrentTask()
        currentTask = Task { [weak self] in
            do {
                guard let self else { return }
                let results = try await self.repository.fetchIssues(fullName: self.fullName, page: 1)
                self.phase = .loaded(LoadedIssues(
                    issues: results,
                    currentPage: 1,
                    hasMorePages: results.count >= Self.perPage
                ))
            } catch is CancellationError {
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .error(message: "Issue の取得に失敗しました")
            }
        }
    }

    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }
}
