import Foundation
import Testing
@testable import github_client_swiftui

@MainActor
struct RepositorySearchCacheTests {

    // MARK: - Helpers

    private func makeResult(repoNames: [String]) -> RepositorySearchPageResult {
        let repos = repoNames.map { name in
            GitHubRepo(
                fullName: GitHubRepoFullName(ownerLogin: "owner", name: name),
                owner: .sampleApple,
                description: nil,
                htmlUrl: URL(string: "https://github.com/owner/\(name)")!,
                stargazersCount: 0,
                forksCount: 0,
                language: nil,
                topics: []
            )
        }
        return RepositorySearchPageResult(
            repositories: repos,
            totalCount: repos.count,
            incompleteResults: false
        )
    }

    private func makeKey(
        q: String = "swift",
        sort: RepositorySearchSort = .default,
        page: Int = 1
    ) -> RepositorySearchCache.Key {
        RepositorySearchCache.Key(q: q, sort: sort, page: page)
    }

    // MARK: - 命中 / 未登録

    @Test func get_returnsStoredValue() {
        let cache = RepositorySearchCache()
        let key = makeKey()
        let value = makeResult(repoNames: ["a", "b"])

        cache.put(key, value: value)

        #expect(cache.get(key) == value)
    }

    @Test func get_returnsNil_forUnknownKey() {
        let cache = RepositorySearchCache()
        #expect(cache.get(makeKey()) == nil)
    }

    // MARK: - キャッシュキーのタプル一意性 (§5.1)

    @Test func keys_differingInQ_areTreatedAsSeparateEntries() {
        let cache = RepositorySearchCache()
        cache.put(makeKey(q: "swift"), value: makeResult(repoNames: ["x"]))
        cache.put(makeKey(q: "rust"), value: makeResult(repoNames: ["y"]))

        #expect(cache.get(makeKey(q: "swift"))?.repositories.first?.fullName.name == "x")
        #expect(cache.get(makeKey(q: "rust"))?.repositories.first?.fullName.name == "y")
    }

    @Test func keys_differingInSortKey_areTreatedAsSeparateEntries() {
        let cache = RepositorySearchCache()
        let stars = RepositorySearchSort(key: .stars, order: .desc)
        let updated = RepositorySearchSort(key: .updated, order: .desc)
        cache.put(makeKey(sort: stars), value: makeResult(repoNames: ["s"]))
        cache.put(makeKey(sort: updated), value: makeResult(repoNames: ["u"]))

        #expect(cache.get(makeKey(sort: stars))?.repositories.first?.fullName.name == "s")
        #expect(cache.get(makeKey(sort: updated))?.repositories.first?.fullName.name == "u")
    }

    @Test func keys_differingInSortOrder_areTreatedAsSeparateEntries() {
        let cache = RepositorySearchCache()
        let asc = RepositorySearchSort(key: .stars, order: .asc)
        let desc = RepositorySearchSort(key: .stars, order: .desc)
        cache.put(makeKey(sort: asc), value: makeResult(repoNames: ["a"]))
        cache.put(makeKey(sort: desc), value: makeResult(repoNames: ["d"]))

        #expect(cache.get(makeKey(sort: asc))?.repositories.first?.fullName.name == "a")
        #expect(cache.get(makeKey(sort: desc))?.repositories.first?.fullName.name == "d")
    }

    @Test func keys_differingInPage_areTreatedAsSeparateEntries() {
        let cache = RepositorySearchCache()
        cache.put(makeKey(page: 1), value: makeResult(repoNames: ["p1"]))
        cache.put(makeKey(page: 2), value: makeResult(repoNames: ["p2"]))

        #expect(cache.get(makeKey(page: 1))?.repositories.first?.fullName.name == "p1")
        #expect(cache.get(makeKey(page: 2))?.repositories.first?.fullName.name == "p2")
    }

    @Test func putOverwritesSameKey() {
        let cache = RepositorySearchCache()
        let key = makeKey()
        cache.put(key, value: makeResult(repoNames: ["old"]))
        cache.put(key, value: makeResult(repoNames: ["new"]))

        #expect(cache.get(key)?.repositories.first?.fullName.name == "new")
    }

    // MARK: - LRU 退避 (§5.4)

    @Test func capacity_isCappedAt100_andEvictsLeastRecentlyUsed_onPut() {
        let cache = RepositorySearchCache()
        for i in 0..<100 {
            cache.put(makeKey(q: "q\(i)"), value: makeResult(repoNames: ["r\(i)"]))
        }
        // 101 件目を投入 → アクセス順で最古の q0 が退避される
        cache.put(makeKey(q: "q100"), value: makeResult(repoNames: ["r100"]))

        #expect(cache.get(makeKey(q: "q0")) == nil)
        #expect(cache.get(makeKey(q: "q1"))?.repositories.first?.fullName.name == "r1")
        #expect(cache.get(makeKey(q: "q100"))?.repositories.first?.fullName.name == "r100")
    }

    @Test func get_promotesEntryAsRecentlyUsed_andProtectsItFromEviction() {
        // §5.4: get 成功でアクセス順が更新される
        let cache = RepositorySearchCache()
        for i in 0..<100 {
            cache.put(makeKey(q: "q\(i)"), value: makeResult(repoNames: ["r\(i)"]))
        }
        // q0 を touch して最新化
        _ = cache.get(makeKey(q: "q0"))
        // 101 件目を投入 → 今度は q0 ではなく次に古い q1 が退避される
        cache.put(makeKey(q: "q100"), value: makeResult(repoNames: ["r100"]))

        #expect(cache.get(makeKey(q: "q0"))?.repositories.first?.fullName.name == "r0")
        #expect(cache.get(makeKey(q: "q1")) == nil)
    }

    // MARK: - invalidate (§5.7, AC-6.1)

    @Test func invalidate_dropsAllPagesForGivenQAndSort_keepingOthers() {
        let cache = RepositorySearchCache()
        let stars = RepositorySearchSort(key: .stars, order: .desc)
        let updated = RepositorySearchSort(key: .updated, order: .desc)

        cache.put(makeKey(q: "swift", sort: stars, page: 1), value: makeResult(repoNames: ["s1"]))
        cache.put(makeKey(q: "swift", sort: stars, page: 2), value: makeResult(repoNames: ["s2"]))
        cache.put(makeKey(q: "swift", sort: updated, page: 1), value: makeResult(repoNames: ["u1"]))
        cache.put(makeKey(q: "rust", sort: stars, page: 1), value: makeResult(repoNames: ["r1"]))

        cache.invalidate(q: "swift", sort: stars)

        #expect(cache.get(makeKey(q: "swift", sort: stars, page: 1)) == nil)
        #expect(cache.get(makeKey(q: "swift", sort: stars, page: 2)) == nil)
        // 別ソート・別クエリは残る
        #expect(cache.get(makeKey(q: "swift", sort: updated, page: 1))?.repositories.first?.fullName.name == "u1")
        #expect(cache.get(makeKey(q: "rust", sort: stars, page: 1))?.repositories.first?.fullName.name == "r1")
    }
}
