import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct IssueDetailModelTests {

    // MARK: - Helpers

    private static let fullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")
    private static let issueNumber = 42

    private func makeSUT(
        issueDetailResult: Result<GitHubIssueDetail, Error> = .success(.sample),
        issueCommentsResult: Result<[GitHubIssueComment], Error> = .success(GitHubIssueComment.samples)
    ) -> (model: IssueDetailModel, mock: MockGithubRepoRepository) {
        let mock = MockGithubRepoRepository(
            issueDetailResult: issueDetailResult,
            issueCommentsResult: issueCommentsResult
        )
        let model = IssueDetailModel(
            fullName: Self.fullName,
            issueNumber: Self.issueNumber,
            repository: mock
        )
        return (model, mock)
    }

    private func waitForInflight(_ model: IssueDetailModel) async {
        await model.inFlightTask?.value
        await model.commentsInFlightTask?.value
    }

    // MARK: - onAppear (detail)

    @Test func initialPhase_isLoading() {
        let (model, _) = makeSUT()
        guard case .loading = model.phase else {
            Issue.record("Expected loading, got \(model.phase)")
            return
        }
        #expect(model.commentsPhase == .idle)
    }

    @Test func onAppear_success_transitionsToLoaded_andLoadsComments() async {
        let (model, mock) = makeSUT()
        model.onAppear()
        await waitForInflight(model)

        guard case let .loaded(detail) = model.phase else {
            Issue.record("Expected loaded, got \(model.phase)")
            return
        }
        #expect(detail == .sample)
        #expect(model.commentsPhase == .loaded)
        #expect(model.comments == GitHubIssueComment.samples)
        await #expect(mock.fetchIssueDetailCallCount == 1)
        await #expect(mock.fetchIssueCommentsCallCount == 1)
    }

    @Test func onAppear_detailFailure_transitionsToError_withoutLoadingComments() async {
        let (model, mock) = makeSUT(
            issueDetailResult: .failure(URLError(.notConnectedToInternet))
        )
        model.onAppear()
        await waitForInflight(model)

        guard case .error = model.phase else {
            Issue.record("Expected error, got \(model.phase)")
            return
        }
        #expect(model.commentsPhase == .idle)
        await #expect(mock.fetchIssueCommentsCallCount == 0)
    }

    @Test func onAppear_calledTwice_doesNotRefetch() async {
        let (model, mock) = makeSUT()
        model.onAppear()
        await waitForInflight(model)
        model.onAppear()
        await waitForInflight(model)
        await #expect(mock.fetchIssueDetailCallCount == 1)
    }

    // MARK: - comments

    @Test func onAppear_detailSuccess_commentsFailure_showsCommentsError() async {
        let (model, _) = makeSUT(
            issueCommentsResult: .failure(URLError(.notConnectedToInternet))
        )
        model.onAppear()
        await waitForInflight(model)

        guard case .loaded = model.phase else {
            Issue.record("Expected loaded for detail")
            return
        }
        guard case .error = model.commentsPhase else {
            Issue.record("Expected comments error, got \(model.commentsPhase)")
            return
        }
    }

    @Test func retryComments_refetchesComments() async {
        let (model, mock) = makeSUT(
            issueCommentsResult: .failure(URLError(.notConnectedToInternet))
        )
        model.onAppear()
        await waitForInflight(model)
        guard case .error = model.commentsPhase else {
            Issue.record("Expected comments error first")
            return
        }

        await mock.setIssueCommentsResult(.success(GitHubIssueComment.samples))
        model.retryComments()
        await model.commentsInFlightTask?.value

        #expect(model.commentsPhase == .loaded)
        #expect(model.comments == GitHubIssueComment.samples)
    }

    // MARK: - retry (detail)

    @Test func retry_afterDetailError_refetchesDetailAndComments() async {
        let (model, mock) = makeSUT(
            issueDetailResult: .failure(URLError(.notConnectedToInternet))
        )
        model.onAppear()
        await waitForInflight(model)

        await mock.setIssueDetailResult(.success(.sample))
        model.retry()
        await waitForInflight(model)

        guard case let .loaded(detail) = model.phase else {
            Issue.record("Expected loaded after retry, got \(model.phase)")
            return
        }
        #expect(detail == .sample)
        #expect(model.commentsPhase == .loaded)
    }

    // MARK: - onDisappear (cancellation)

    @Test func onDisappear_cancelsBothTasks() async {
        let (model, mock) = makeSUT()
        await mock.setIssueDetailAsyncHandler { @Sendable _, _ in
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        model.onAppear()
        await Task.yield()
        model.onDisappear()
        await waitForInflight(model)
        #expect(model.inFlightTask == nil)
        #expect(model.commentsInFlightTask == nil)
    }
}
