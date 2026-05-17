import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
@Suite(.serialized)
struct RepositorySearchModelPersistenceTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RepositorySearchModelPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSUT(
        defaults: UserDefaults? = nil,
        searchResult: Result<RepositorySearchPageResult, Error>? = nil,
        debounceDuration: Duration = .milliseconds(0)
    ) -> (
        model: RepositorySearchModel,
        mock: MockGithubRepoRepository,
        store: RepositorySearchConditionStore,
        defaults: UserDefaults
    ) {
        let defaults = defaults ?? makeDefaults()
        let store = RepositorySearchConditionStore(defaults: defaults)
        let mock = MockGithubRepoRepository(
            searchResult: searchResult ?? .success(.init(
                repositories: GitHubRepo.samples,
                totalCount: GitHubRepo.samples.count,
                incompleteResults: false
            ))
        )
        let model = RepositorySearchModel(
            repository: mock,
            debounceDuration: debounceDuration,
            conditionStore: store
        )
        return (model, mock, store, defaults)
    }

    private func waitTick(_ ms: Int = 50) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: - 起動時の復元

    @Test func initWithoutSavedSnapshot_usesDefaults_andStaysIdle() async {
        let (model, mock, _, _) = makeSUT()
        await waitTick()

        #expect(model.appliedQualifiers == .empty)
        #expect(model.sort == .default)
        #expect(model.query == "")
        #expect(model.phase == .idle)
        await #expect(mock.searchCallCount == 0)
    }

    @Test func initWithSavedSnapshot_restoresQualifiersAndSort_andStaysIdle() async {
        let defaults = makeDefaults()
        let preStore = RepositorySearchConditionStore(defaults: defaults)
        let saved = RepositorySearchConditionSnapshot(
            qualifiers: RepositorySearchQualifiers(
                inTargets: [.name],
                language: GitHubLanguage(name: "Swift"),
                stars: .init(min: 100, max: nil),
                pushed: .init(from: nil, to: nil),
                topics: ["ios"]
            ),
            sort: RepositorySearchSort(key: .updated, order: .asc)
        )
        preStore.save(saved)

        let (model, mock, _, _) = makeSUT(defaults: defaults)
        await waitTick()

        #expect(model.appliedQualifiers == saved.qualifiers)
        #expect(model.sort == saved.sort)
        #expect(model.query == "")
        #expect(model.phase == .idle)
        await #expect(mock.searchCallCount == 0)
    }

    @Test func initWithCorruptedSnapshot_fallsBackToDefaults() async {
        let defaults = makeDefaults()
        defaults.set(Data("not a json".utf8), forKey: RepositorySearchConditionStore.storageKey)

        let (model, mock, _, defaultsOut) = makeSUT(defaults: defaults)
        await waitTick()

        #expect(model.appliedQualifiers == .empty)
        #expect(model.sort == .default)
        #expect(model.phase == .idle)
        await #expect(mock.searchCallCount == 0)
        #expect(defaultsOut.data(forKey: RepositorySearchConditionStore.storageKey) == nil)
    }

    @Test func restoredQualifiersAreUsed_whenKeywordIsTyped() async {
        let defaults = makeDefaults()
        let preStore = RepositorySearchConditionStore(defaults: defaults)
        preStore.save(RepositorySearchConditionSnapshot(
            qualifiers: RepositorySearchQualifiers(
                inTargets: [],
                language: GitHubLanguage(name: "Swift"),
                stars: .init(min: nil, max: nil),
                pushed: .init(from: nil, to: nil),
                topics: []
            ),
            sort: RepositorySearchSort(key: .updated, order: .desc)
        ))

        let (model, mock, _, _) = makeSUT(defaults: defaults)
        model.query = "ui"
        await waitTick()

        await #expect(mock.searchCallCount == 1)
        await #expect(mock.lastQuery?.contains("language:Swift") == true)
        await #expect(mock.lastSort == "updated")
    }

    // MARK: - 自動保存

    @Test func applyQualifiers_savesSnapshot() async {
        let (model, _, store, _) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")

        model.applyQualifiers(q)
        await waitTick()

        let loaded = store.load()
        #expect(loaded?.qualifiers == q)
        #expect(loaded?.sort == .default)
    }

    @Test func setSort_savesSnapshot() async {
        let (model, _, store, _) = makeSUT()

        model.setSort(RepositorySearchSort(key: .updated, order: .desc))
        await waitTick()

        let loaded = store.load()
        #expect(loaded?.sort == RepositorySearchSort(key: .updated, order: .desc))
        #expect(loaded?.qualifiers == .empty)
    }

    @Test func applyQualifiers_overwritesPreviousSnapshot() async {
        let (model, _, store, _) = makeSUT()
        var first = RepositorySearchQualifiers.empty
        first.language = GitHubLanguage(name: "Swift")
        model.applyQualifiers(first)
        await waitTick()

        var second = RepositorySearchQualifiers.empty
        second.topics = ["ios"]
        model.applyQualifiers(second)
        await waitTick()

        #expect(store.load()?.qualifiers == second)
    }

    @Test func removeChip_savesSnapshot() async {
        let (model, _, store, _) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        q.topics = ["ios", "swiftui"]
        model.applyQualifiers(q)
        await waitTick()

        model.removeChip(.topic(label: "#ios", value: "ios"))
        await waitTick()

        let loaded = store.load()
        #expect(loaded?.qualifiers.topics == ["swiftui"])
        #expect(loaded?.qualifiers.language == GitHubLanguage(name: "Swift"))
    }

    // MARK: - 自動削除 (qualifier 空 + sort 既定)

    @Test func applyingEmptyQualifiers_withDefaultSort_clearsSnapshot() async {
        let (model, _, store, _) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        model.applyQualifiers(q)
        await waitTick()
        #expect(store.load() != nil)

        model.applyQualifiers(.empty)
        await waitTick()

        #expect(store.load() == nil)
    }

    @Test func removingLastChip_withDefaultSort_clearsSnapshot() async {
        let (model, _, store, _) = makeSUT()
        var q = RepositorySearchQualifiers.empty
        q.language = GitHubLanguage(name: "Swift")
        model.applyQualifiers(q)
        await waitTick()
        #expect(store.load() != nil)

        model.removeChip(.language(label: "Swift"))
        await waitTick()

        #expect(store.load() == nil)
    }

    @Test func sortReturnsToDefault_withEmptyQualifiers_clearsSnapshot() async {
        let (model, _, store, _) = makeSUT()
        model.setSort(RepositorySearchSort(key: .updated, order: .asc))
        await waitTick()
        #expect(store.load() != nil)

        model.setSort(.default)
        await waitTick()

        #expect(store.load() == nil)
    }

    // MARK: - 保存しない操作 (AC-2.4)

    @Test func keywordChanges_doNotPersist() async {
        let (model, _, store, _) = makeSUT()

        model.query = "swift"
        await waitTick()
        #expect(store.load() == nil)

        model.query = ""
        await waitTick()
        #expect(store.load() == nil)
    }

    @Test func paginationOperations_doNotPersist() async {
        let page1 = (1...30).map { id in
            GitHubRepo(
                fullName: GitHubRepoFullName(ownerLogin: "owner", name: "repo-\(id)"),
                owner: .sampleApple,
                description: nil,
                htmlUrl: URL(string: "https://github.com/owner/repo-\(id)")!,
                stargazersCount: 0,
                forksCount: 0,
                language: nil,
                topics: []
            )
        }
        let (model, mock, store, _) = makeSUT(
            searchResult: .success(.init(repositories: page1, totalCount: 100, incompleteResults: false))
        )
        model.query = "swift"
        await waitTick()
        #expect(store.load() == nil) // キーワード変更だけでは保存しない

        await mock.setSearchResult(.success(.init(repositories: page1, totalCount: 100, incompleteResults: false)))
        model.loadNextPageIfNeeded()
        await waitTick()

        #expect(store.load() == nil)
    }
}
