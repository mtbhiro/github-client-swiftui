import Foundation

@Observable
final class IssueDetailModel {
    private(set) var phase: Phase = .loading
    private(set) var comments: [GitHubIssueComment] = []
    private(set) var commentsPhase: CommentsPhase = .idle

    let fullName: GitHubRepoFullName
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
        fullName: GitHubRepoFullName,
        issueNumber: Int,
        repository: GithubRepoRepositoryProtocol = GithubRepoRepository()
    ) {
        self.fullName = fullName
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
                    fullName: fullName, number: issueNumber
                )
                phase = .loaded(detail)
                loadComments()
            } catch is CancellationError {
            } catch {
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
                    fullName: fullName, number: issueNumber, page: 1
                )
                comments = result
                commentsPhase = .loaded
            } catch is CancellationError {
            } catch {
                commentsPhase = .error("コメントの取得に失敗しました")
            }
        }
    }
}
