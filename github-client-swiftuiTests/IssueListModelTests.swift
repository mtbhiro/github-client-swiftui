import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct IssueListModelTests {

    // MARK: - Helpers

    private static let fullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")

    private func makeSUT(
        issuesResult: Result<[GitHubIssue], Error> = .success(GitHubIssue.samples)
    ) -> (model: IssueListModel, mock: MockGithubRepoRepository) {
        let mock = MockGithubRepoRepository(issuesResult: issuesResult)
        let model = IssueListModel(fullName: Self.fullName, repository: mock)
        return (model, mock)
    }

    private func makeIssues(count: Int, startId: Int = 1) -> [GitHubIssue] {
        (startId..<startId + count).map { id in
            GitHubIssue(
                id: id,
                number: id,
                title: "Issue \(id)",
                state: .open,
                user: .sampleOctocat,
                labels: [],
                commentsCount: 0,
                createdAt: Date(timeIntervalSince1970: 0),
                isPullRequest: false
            )
        }
    }

    private func waitForInflight(_ model: IssueListModel) async {
        await model.inFlightTask?.value
    }

    // MARK: - onAppear

    @Test func initialPhase_isLoading() {
        let (model, _) = makeSUT()
        guard case .loading = model.phase else {
            Issue.record("Expected loading, got \(model.phase)")
            return
        }
    }

    @Test func onAppear_success_transitionsToLoaded() async {
        let (model, mock) = makeSUT()
        model.onAppear()
        await waitForInflight(model)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded, got \(model.phase)")
            return
        }
        #expect(state.issues == GitHubIssue.samples)
        #expect(state.currentPage == 1)
        await #expect(mock.fetchIssuesCallCount == 1)
    }

    @Test func onAppear_failure_transitionsToError() async {
        let (model, _) = makeSUT(issuesResult: .failure(URLError(.notConnectedToInternet)))
        model.onAppear()
        await waitForInflight(model)
        guard case .error = model.phase else {
            Issue.record("Expected error, got \(model.phase)")
            return
        }
    }

    @Test func onAppear_calledTwice_doesNotRefetch() async {
        let (model, mock) = makeSUT()
        model.onAppear()
        await waitForInflight(model)
        model.onAppear()
        await waitForInflight(model)
        await #expect(mock.fetchIssuesCallCount == 1)
    }

    // MARK: - pagination

    @Test func fullPage_setsHasMorePages() async {
        let fullPage = makeIssues(count: IssueListModel.perPage)
        let (model, _) = makeSUT(issuesResult: .success(fullPage))
        model.onAppear()
        await waitForInflight(model)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded")
            return
        }
        #expect(state.hasMorePages == true)
    }

    @Test func partialPage_setsHasMorePagesFalse() async {
        let partial = makeIssues(count: 5)
        let (model, _) = makeSUT(issuesResult: .success(partial))
        model.onAppear()
        await waitForInflight(model)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded")
            return
        }
        #expect(state.hasMorePages == false)
    }

    @Test func loadNextPage_appendsResults() async {
        let page1 = makeIssues(count: IssueListModel.perPage, startId: 1)
        let page2 = makeIssues(count: 5, startId: 31)
        let (model, mock) = makeSUT(issuesResult: .success(page1))
        model.onAppear()
        await waitForInflight(model)

        await mock.setIssuesResult(.success(page2))
        model.loadNextPageIfNeeded()
        await waitForInflight(model)

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after paging")
            return
        }
        #expect(state.issues.count == IssueListModel.perPage + 5)
        #expect(state.currentPage == 2)
        #expect(state.hasMorePages == false)
        await #expect(mock.fetchIssuesLastPage == 2)
    }

    @Test func loadNextPage_failure_keepsExistingItems_andStopsLoadingMore() async {
        let page1 = makeIssues(count: IssueListModel.perPage, startId: 1)
        let (model, mock) = makeSUT(issuesResult: .success(page1))
        model.onAppear()
        await waitForInflight(model)

        await mock.setIssuesResult(.failure(URLError(.notConnectedToInternet)))
        model.loadNextPageIfNeeded()
        await waitForInflight(model)

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded (preserves existing items), got \(model.phase)")
            return
        }
        #expect(state.issues.count == IssueListModel.perPage)
        #expect(state.isLoadingMore == false)
    }

    @Test func loadNextPage_whenNoMorePages_doesNotFetch() async {
        let partial = makeIssues(count: 5)
        let (model, mock) = makeSUT(issuesResult: .success(partial))
        model.onAppear()
        await waitForInflight(model)
        let baseline = await mock.fetchIssuesCallCount

        model.loadNextPageIfNeeded()
        await waitForInflight(model)

        await #expect(mock.fetchIssuesCallCount == baseline)
    }

    // MARK: - retry

    @Test func retry_afterError_refetches() async {
        let (model, mock) = makeSUT(issuesResult: .failure(URLError(.notConnectedToInternet)))
        model.onAppear()
        await waitForInflight(model)
        guard case .error = model.phase else {
            Issue.record("Expected error first")
            return
        }

        await mock.setIssuesResult(.success(GitHubIssue.samples))
        model.retry()
        await waitForInflight(model)
        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after retry, got \(model.phase)")
            return
        }
        #expect(state.issues == GitHubIssue.samples)
    }

    // MARK: - refresh

    @Test func refresh_replacesResults() async {
        let initial = makeIssues(count: 3, startId: 1)
        let refreshed = makeIssues(count: 2, startId: 100)
        let (model, mock) = makeSUT(issuesResult: .success(initial))
        model.onAppear()
        await waitForInflight(model)

        await mock.setIssuesResult(.success(refreshed))
        await model.refresh()

        guard case let .loaded(state) = model.phase else {
            Issue.record("Expected loaded after refresh")
            return
        }
        #expect(state.issues == refreshed)
        #expect(state.currentPage == 1)
    }

    @Test func refresh_failure_transitionsToError() async {
        let initial = makeIssues(count: 3, startId: 1)
        let (model, mock) = makeSUT(issuesResult: .success(initial))
        model.onAppear()
        await waitForInflight(model)

        await mock.setIssuesResult(.failure(URLError(.timedOut)))
        await model.refresh()

        guard case .error = model.phase else {
            Issue.record("Expected error after refresh failure, got \(model.phase)")
            return
        }
    }

    // MARK: - onDisappear (cancellation)

    @Test func onDisappear_cancelsInflightTask() async {
        let (model, _) = makeSUT()
        model.onAppear()
        model.onDisappear()
        await waitForInflight(model)
        #expect(model.inFlightTask == nil)
    }
}
