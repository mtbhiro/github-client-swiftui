import Foundation

@Observable
final class RepositoryDetailModel {
    private(set) var phase: Phase = .loading
    private let ownerLogin: String
    private let repositoryName: String
    private let repository: GithubRepoRepositoryProtocol
    private var loadTask: Task<Void, Never>?

    enum Phase {
        case loading
        case loaded(GitHubRepoDetail)
        case error(String)
    }

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

    func retry() {
        phase = .loading
        load()
    }

    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func load() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let repo = try await repository.fetchRepository(
                    owner: ownerLogin,
                    name: repositoryName
                )
                guard !Task.isCancelled else { return }
                phase = .loaded(repo)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error("リポジトリの取得に失敗しました")
            }
        }
    }
}
