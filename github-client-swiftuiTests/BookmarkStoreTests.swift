import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct BookmarkStoreTests {

    // MARK: - Helpers

    private static let sampleRepo = BookmarkItem.repository(RepositoryBookmark(
        fullName: GitHubRepoFullName(ownerLogin: "apple", name: "swift"),
        description: "The Swift Programming Language",
        stargazersCount: 67000,
        language: "C++",
        createdAt: Date(timeIntervalSince1970: 0)
    ))

    private static let sampleRepo2 = BookmarkItem.repository(RepositoryBookmark(
        fullName: GitHubRepoFullName(ownerLogin: "google", name: "go"),
        description: nil,
        stargazersCount: 120000,
        language: "Go",
        createdAt: Date(timeIntervalSince1970: 100)
    ))

    private static let sampleIssue = BookmarkItem.issue(IssueBookmark(
        fullName: GitHubRepoFullName(ownerLogin: "apple", name: "swift"),
        number: 42,
        title: "Bug report",
        state: .open,
        isPullRequest: false,
        createdAt: Date(timeIntervalSince1970: 200)
    ))

    private func makePersistentStore() -> (store: BookmarkStore, defaults: UserDefaults) {
        let suiteName = "BookmarkStoreTests.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (BookmarkStore(defaults: defaults), defaults)
    }

    // MARK: - add / remove / contains

    @Test func initialState_isEmpty() {
        let store = BookmarkStore(items: [])
        #expect(store.items.isEmpty)
    }

    @Test func add_insertsAtFront() {
        let store = BookmarkStore(items: [])
        store.add(Self.sampleRepo)
        store.add(Self.sampleIssue)
        #expect(store.items.count == 2)
        #expect(store.items.first == Self.sampleIssue)
    }

    @Test func add_duplicateIsIgnored() {
        let store = BookmarkStore(items: [])
        store.add(Self.sampleRepo)
        store.add(Self.sampleRepo)
        #expect(store.items.count == 1)
    }

    @Test func remove_deletesMatchingItem() {
        let store = BookmarkStore(items: [Self.sampleRepo, Self.sampleIssue])
        store.remove(Self.sampleRepo)
        #expect(store.items == [Self.sampleIssue])
    }

    @Test func remove_nonExistent_doesNothing() {
        let store = BookmarkStore(items: [Self.sampleRepo])
        store.remove(Self.sampleIssue)
        #expect(store.items.count == 1)
    }

    @Test func contains_returnsTrueForExistingItem() {
        let store = BookmarkStore(items: [Self.sampleRepo])
        #expect(store.contains(Self.sampleRepo))
        #expect(!store.contains(Self.sampleIssue))
    }

    // MARK: - toggle

    @Test func toggle_addsWhenAbsent_removesWhenPresent() {
        let store = BookmarkStore(items: [])
        store.toggle(Self.sampleRepo)
        #expect(store.contains(Self.sampleRepo))

        store.toggle(Self.sampleRepo)
        #expect(!store.contains(Self.sampleRepo))
    }

    // MARK: - filtering

    @Test func repositories_returnsOnlyRepositories() {
        let store = BookmarkStore(items: [Self.sampleRepo, Self.sampleIssue, Self.sampleRepo2])
        let repos = store.repositories()
        #expect(repos.count == 2)
        for item in repos {
            #expect(item.isRepository)
        }
    }

    @Test func issues_returnsOnlyIssues() {
        let store = BookmarkStore(items: [Self.sampleRepo, Self.sampleIssue])
        let issues = store.issues()
        #expect(issues.count == 1)
        for item in issues {
            #expect(item.isIssue)
        }
    }

    // MARK: - persistence round-trip

    @Test func persistence_savedItems_areRestoredOnInit() {
        let (store, defaults) = makePersistentStore()
        store.add(Self.sampleIssue)
        store.add(Self.sampleRepo)

        let restored = BookmarkStore(defaults: defaults)
        #expect(restored.items.count == 2)
        #expect(restored.contains(Self.sampleRepo))
        #expect(restored.contains(Self.sampleIssue))
    }

    @Test func persistence_removeIsPersisted() {
        let (store, defaults) = makePersistentStore()
        store.add(Self.sampleRepo)
        store.add(Self.sampleIssue)
        store.remove(Self.sampleRepo)

        let restored = BookmarkStore(defaults: defaults)
        #expect(restored.items.count == 1)
        #expect(!restored.contains(Self.sampleRepo))
    }

    @Test func inMemoryInit_doesNotPersist() {
        let store = BookmarkStore(items: [Self.sampleRepo])
        store.add(Self.sampleIssue)
        #expect(store.items.count == 2)
    }
}
