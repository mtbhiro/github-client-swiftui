import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchModelTests {

    private func makeSUT(
        result: Result<[GitHubRepo], Error>? = nil,
        debounceDuration: Duration = .milliseconds(0)
    ) -> (model: RepositorySearchModel, mock: MockRepositorySearchRepository) {
        let mock = MockRepositorySearchRepository()
        mock.result = result ?? .success(GitHubRepo.samples)
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: debounceDuration
        )
        return (model, mock)
    }

    @Test func initialState_isIdle() {
        let (model, _) = makeSUT()
        #expect(model.query == "")
        #expect(model.phase == .idle)
        #expect(model.repositories.isEmpty)
    }

    @Test func settingEmptyQuery_remainsIdle() {
        let (model, _) = makeSUT()
        model.query = "   "
        #expect(model.phase == .idle)
    }

    @Test func settingQuery_transitionsToLoading() {
        let (model, _) = makeSUT()
        model.query = "swift"
        #expect(model.phase == .loading)
    }

    @Test func clearQuery_resetsToIdle() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.clearQuery()
        #expect(model.query == "")
        #expect(model.phase == .idle)
        #expect(model.repositories.isEmpty)
    }

    @Test func onSubmit_transitionsToLoading() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.onSubmit()
        #expect(model.phase == .loading)
    }

    @Test func onDisappear_cancelsSearch() async {
        let (model, _) = makeSUT(debounceDuration: .seconds(10))
        model.query = "swift"
        model.onDisappear()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loading)
    }

    @Test func retry_startsSearchAgain() {
        let (model, _) = makeSUT()
        model.query = "swift"
        model.retry()
        #expect(model.phase == .loading)
    }

    @Test func search_success_loadsRepositories() async throws {
        let (model, mock) = makeSUT()
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loaded(isEmpty: false))
        #expect(model.repositories == GitHubRepo.samples)
        #expect(mock.lastQuery == "swift")
        #expect(mock.lastPage == 1)
    }

    @Test func search_emptyResult_loadsEmpty() async throws {
        let (model, _) = makeSUT(result: .success([]))
        model.query = "nonexistent"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loaded(isEmpty: true))
        #expect(model.repositories.isEmpty)
    }

    @Test func search_failure_showsError() async throws {
        let (model, _) = makeSUT(result: .failure(URLError(.notConnectedToInternet)))
        model.query = "swift"
        model.onSubmit()
        try await Task.sleep(for: .milliseconds(50))
        guard case .error = model.phase else {
            Issue.record("Expected error phase")
            return
        }
    }

    @Test func queryChange_debounces() async throws {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(100))
        model.query = "s"
        model.query = "sw"
        model.query = "swi"
        #expect(model.phase == .loading)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mock.searchCallCount == 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.searchCallCount == 1)
        #expect(mock.lastQuery == "swi")
    }

    @Test func newSearch_cancelsPrevious() async throws {
        let (model, mock) = makeSUT(debounceDuration: .milliseconds(50))
        model.query = "first"
        try await Task.sleep(for: .milliseconds(30))
        model.query = "second"
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.lastQuery == "second")
    }
}
