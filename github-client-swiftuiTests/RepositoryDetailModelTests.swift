import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositoryDetailModelTests {

    // MARK: - Helpers

    private static let fullName = GitHubRepoFullName(ownerLogin: "apple", name: "swift")

    private func makeSUT(
        fetchResult: Result<GitHubRepoDetail, Error> = .success(.sampleSwift)
    ) -> (model: RepositoryDetailModel, mock: MockGithubRepoRepository) {
        let mock = MockGithubRepoRepository(fetchResult: fetchResult)
        let model = RepositoryDetailModel(fullName: Self.fullName, repository: mock)
        return (model, mock)
    }

    private func waitForInflight(_ model: RepositoryDetailModel) async {
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
        guard case let .loaded(detail) = model.phase else {
            Issue.record("Expected loaded, got \(model.phase)")
            return
        }
        #expect(detail == .sampleSwift)
        await #expect(mock.fetchRepositoryCallCount == 1)
    }

    @Test func onAppear_failure_transitionsToError() async {
        let (model, _) = makeSUT(fetchResult: .failure(URLError(.notConnectedToInternet)))
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
        await #expect(mock.fetchRepositoryCallCount == 1)
    }

    // MARK: - retry

    @Test func retry_afterError_refetches() async {
        let (model, mock) = makeSUT(fetchResult: .failure(URLError(.notConnectedToInternet)))
        model.onAppear()
        await waitForInflight(model)
        guard case .error = model.phase else {
            Issue.record("Expected error phase first")
            return
        }

        await mock.setFetchResult(.success(.sampleSwift))
        model.retry()
        await waitForInflight(model)
        guard case let .loaded(detail) = model.phase else {
            Issue.record("Expected loaded after retry, got \(model.phase)")
            return
        }
        #expect(detail == .sampleSwift)
    }

    // MARK: - onDisappear (cancellation)

    @Test func onDisappear_cancelsInflightTask() async {
        let (model, mock) = makeSUT()
        await mock.setFetchAsyncHandler { @Sendable _ in
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        model.onAppear()
        await Task.yield()
        model.onDisappear()
        await waitForInflight(model)
        guard case .loading = model.phase else {
            Issue.record("Expected loading (cancelled before completion), got \(model.phase)")
            return
        }
    }
}
