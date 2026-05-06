import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchModelTests {

    @Test func initialState_isIdle() {
        let model = RepositorySearchModel()
        #expect(model.query == "")
        #expect(model.phase == .idle)
    }

    @Test func settingEmptyQuery_remainsIdle() {
        let model = RepositorySearchModel()
        model.query = "   "
        #expect(model.phase == .idle)
    }

    @Test func settingQuery_transitionsToLoading() {
        let model = RepositorySearchModel()
        model.query = "swift"
        #expect(model.phase == .loading)
    }

    @Test func clearQuery_resetsToIdle() {
        let model = RepositorySearchModel()
        model.query = "swift"
        model.clearQuery()
        #expect(model.query == "")
        #expect(model.phase == .idle)
    }

    @Test func onSubmit_transitionsToLoading() {
        let model = RepositorySearchModel()
        model.query = "swift"
        model.onSubmit()
        #expect(model.phase == .loading)
    }

    @Test func onDisappear_cancelsSearch() async {
        let model = RepositorySearchModel()
        model.query = "swift"
        model.onDisappear()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.phase == .loading)
    }

    @Test func retry_startsSearchAgain() {
        let model = RepositorySearchModel()
        model.query = "swift"
        model.retry()
        #expect(model.phase == .loading)
    }

    @Test func queryChange_debounces() async throws {
        let model = RepositorySearchModel()
        model.query = "s"
        model.query = "sw"
        model.query = "swi"
        #expect(model.phase == .loading)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.phase == .loading)
    }
}
