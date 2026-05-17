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

    // MARK: - 命中・失効 (AC-2.1, AC-2.3)

    @Test func get_returnsStoredValue_whenWithinTTL() {
        let clock = MutableClock(currentDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = RepositorySearchCache(now: clock.now)
        let key = makeKey()
        let value = makeResult(repoNames: ["a", "b"])

        cache.put(key, value: value)
        let got = cache.get(key)

        #expect(got == value)
    }

    @Test func get_returnsValue_at60SecondsExactly_isHit() {
        // AC-2.3: 60 秒以下は命中 (`<= 60` 秒は命中)
        let clock = MutableClock(currentDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = RepositorySearchCache(now: clock.now)
        let key = makeKey()
        let value = makeResult(repoNames: ["a"])

        cache.put(key, value: value)
        clock.advance(seconds: 60)
        let got = cache.get(key)

        #expect(got == value)
    }

    @Test func get_returnsNil_pastTTL_andDropsEntry() {
        // AC-2.3: 60 秒超で失効
        let clock = MutableClock(currentDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = RepositorySearchCache(now: clock.now)
        let key = makeKey()
        let value = makeResult(repoNames: ["a"])

        cache.put(key, value: value)
        clock.advance(seconds: 60.001)
        let got = cache.get(key)

        #expect(got == nil)
        // 失効したエントリは破棄され、時間を戻しても復活しない
        clock.advance(seconds: -10)
        #expect(cache.get(key) == nil)
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

    @Test func putOverwritesSameKey_andRefreshesStoredAt() {
        let clock = MutableClock(currentDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = RepositorySearchCache(now: clock.now)
        let key = makeKey()

        cache.put(key, value: makeResult(repoNames: ["old"]))
        clock.advance(seconds: 59)
        cache.put(key, value: makeResult(repoNames: ["new"]))
        // 上書き時点で stored_at が更新されるので、ここからさらに 60 秒以内なら命中
        clock.advance(seconds: 60)

        #expect(cache.get(key)?.repositories.first?.fullName.name == "new")
    }

    // MARK: - サイズ上限 (§5.4)

    @Test func capacity_isCappedAt100_andEvictsOldestFirst() {
        // §5.4: 100 件上限、最も古い stored_at から順に破棄 (FIFO)
        let clock = MutableClock(currentDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = RepositorySearchCache(now: clock.now)

        for i in 0..<100 {
            cache.put(makeKey(q: "q\(i)"), value: makeResult(repoNames: ["r\(i)"]))
            clock.advance(seconds: 0.001)
        }
        // 101 件目を投入すると、最古の q0 が evict される
        cache.put(makeKey(q: "q100"), value: makeResult(repoNames: ["r100"]))

        #expect(cache.get(makeKey(q: "q0")) == nil)
        #expect(cache.get(makeKey(q: "q1"))?.repositories.first?.fullName.name == "r1")
        #expect(cache.get(makeKey(q: "q100"))?.repositories.first?.fullName.name == "r100")
    }
}
