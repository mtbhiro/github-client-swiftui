import Foundation

enum IssueListPhase: Sendable, Equatable {
    case loading
    case loaded(isEmpty: Bool)
    case error(message: String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

@Observable
final class IssueListModel {
    private(set) var phase: IssueListPhase = .loading
    private(set) var issues: [GitHubIssue] = []
    private(set) var isLoadingMore: Bool = false
    private(set) var hasMorePages: Bool = false

    let ownerLogin: String
    let repositoryName: String

    private static let perPage = 30
    private var currentPage: Int = 1
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private let repository: GithubRepoRepositoryProtocol

    init(
        ownerLogin: String,
        repositoryName: String,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        self.ownerLogin = ownerLogin
        self.repositoryName = repositoryName
        self.repository = repository
    }

    func onAppear() {
        guard case .loading = phase else { return }
        load()
    }

    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
    }

    func retry() {
        phase = .loading
        load()
    }

    func refresh() async {
        loadTask?.cancel()
        loadTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil

        do {
            let results = try await repository.fetchIssues(
                owner: ownerLogin, repo: repositoryName, page: 1
            )
            issues = results
            currentPage = 1
            hasMorePages = results.count >= Self.perPage
            phase = .loaded(isEmpty: results.isEmpty)
        } catch is CancellationError {
        } catch {
            phase = .error(message: "Issue の取得に失敗しました")
        }
    }

    func loadNextPageIfNeeded() {
        guard hasMorePages, !isLoadingMore, phase.isLoaded else { return }

        let nextPage = currentPage + 1
        isLoadingMore = true
        loadMoreTask = Task { [weak self] in
            do {
                let results = try await self?.repository.fetchIssues(
                    owner: self?.ownerLogin ?? "",
                    repo: self?.repositoryName ?? "",
                    page: nextPage
                ) ?? []
                try Task.checkCancellation()
                guard let self else { return }
                self.issues.append(contentsOf: results)
                self.currentPage = nextPage
                self.hasMorePages = results.count >= Self.perPage
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
            }
            self?.isLoadingMore = false
        }
    }

    private func load() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let results = try await repository.fetchIssues(
                    owner: ownerLogin, repo: repositoryName, page: 1
                )
                guard !Task.isCancelled else { return }
                issues = results
                currentPage = 1
                hasMorePages = results.count >= Self.perPage
                phase = .loaded(isEmpty: results.isEmpty)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error(message: "Issue の取得に失敗しました")
            }
        }
    }
}
