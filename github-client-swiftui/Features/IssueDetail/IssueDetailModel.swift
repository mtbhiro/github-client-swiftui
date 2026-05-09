import Foundation

@Observable
final class IssueDetailModel {
    private(set) var phase: Phase = .loading
    private(set) var comments: [GitHubIssueComment] = []
    private(set) var commentsPhase: CommentsPhase = .idle

    let ownerLogin: String
    let repositoryName: String
    let issueNumber: Int

    private let repository: GithubRepoRepositoryProtocol
    private var loadTask: Task<Void, Never>?
    private var commentsTask: Task<Void, Never>?

    enum Phase {
        case loading
        case loaded(GitHubIssueDetail)
        case error(String)
    }

    enum CommentsPhase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    init(
        ownerLogin: String,
        repositoryName: String,
        issueNumber: Int,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        self.ownerLogin = ownerLogin
        self.repositoryName = repositoryName
        self.issueNumber = issueNumber
        self.repository = repository
    }

    func onAppear() {
        guard case .loading = phase else { return }
        load()
    }

    func onDisappear() {
        loadTask?.cancel()
        loadTask = nil
        commentsTask?.cancel()
        commentsTask = nil
    }

    func retry() {
        phase = .loading
        load()
    }

    func retryComments() {
        loadComments()
    }

    private func load() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let detail = try await repository.fetchIssueDetail(
                    owner: ownerLogin, repo: repositoryName, number: issueNumber
                )
                guard !Task.isCancelled else { return }
                phase = .loaded(detail)
                loadComments()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error("Issue の取得に失敗しました")
            }
        }
    }

    private func loadComments() {
        commentsTask?.cancel()
        commentsPhase = .loading
        commentsTask = Task {
            do {
                let result = try await repository.fetchIssueComments(
                    owner: ownerLogin, repo: repositoryName, number: issueNumber, page: 1
                )
                guard !Task.isCancelled else { return }
                comments = result
                commentsPhase = .loaded
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                commentsPhase = .error("コメントの取得に失敗しました")
            }
        }
    }
}
