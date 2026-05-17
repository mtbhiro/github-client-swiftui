import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchConditionStoreTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RepositorySearchConditionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func sampleSnapshot() -> RepositorySearchConditionSnapshot {
        RepositorySearchConditionSnapshot(
            qualifiers: RepositorySearchQualifiers(
                inTargets: [.name, .readme],
                language: GitHubLanguage(name: "Swift"),
                stars: .init(min: 50, max: nil),
                pushed: .init(from: "2025-01-01", to: "2025-12-31"),
                topics: ["ios"]
            ),
            sort: RepositorySearchSort(key: .updated, order: .asc)
        )
    }

    @Test func load_returnsNil_whenNothingSaved() {
        let store = RepositorySearchConditionStore(defaults: makeDefaults())
        #expect(store.load() == nil)
    }

    @Test func save_thenLoad_roundTrip() {
        let store = RepositorySearchConditionStore(defaults: makeDefaults())
        let snapshot = sampleSnapshot()

        store.save(snapshot)
        let loaded = store.load()

        #expect(loaded == snapshot)
    }

    @Test func save_overwritesPreviousValue() {
        let store = RepositorySearchConditionStore(defaults: makeDefaults())
        store.save(sampleSnapshot())

        let overwritten = RepositorySearchConditionSnapshot(
            qualifiers: RepositorySearchQualifiers(
                inTargets: [.description],
                language: nil,
                stars: .init(min: nil, max: 999),
                pushed: .init(from: nil, to: nil),
                topics: []
            ),
            sort: .default
        )
        store.save(overwritten)

        #expect(store.load() == overwritten)
    }

    @Test func clear_removesSavedSnapshot() {
        let store = RepositorySearchConditionStore(defaults: makeDefaults())
        store.save(sampleSnapshot())
        #expect(store.load() != nil)

        store.clear()

        #expect(store.load() == nil)
    }

    @Test func load_corruptedData_returnsNil_andRemovesIt() {
        let defaults = makeDefaults()
        defaults.set(Data("garbage".utf8), forKey: RepositorySearchConditionStore.storageKey)

        let store = RepositorySearchConditionStore(defaults: defaults)

        #expect(store.load() == nil)
        #expect(defaults.data(forKey: RepositorySearchConditionStore.storageKey) == nil)
    }
}
