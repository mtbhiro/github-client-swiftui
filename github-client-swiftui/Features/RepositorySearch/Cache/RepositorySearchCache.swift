import Foundation

/// リポジトリ検索結果の短期メモリキャッシュ (PRD: repository-search-cache.md §5)。
/// 同期参照前提 (AC-1.1) のため、View Model と同じ MainActor 上で動く UI 状態の付属物として扱う。
final class RepositorySearchCache {

    struct Key: Hashable, Sendable {
        let q: String
        let sort: RepositorySearchSort
        let page: Int
    }

    static let ttl: TimeInterval = 60
    static let capacity = 100

    private struct Entry {
        let value: RepositorySearchPageResult
        let storedAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func get(_ key: Key) -> RepositorySearchPageResult? {
        guard let entry = entries[key] else { return nil }
        let elapsed = now().timeIntervalSince(entry.storedAt)
        if elapsed > Self.ttl {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func put(_ key: Key, value: RepositorySearchPageResult) {
        entries[key] = Entry(value: value, storedAt: now())
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        guard entries.count > Self.capacity else { return }
        // FIFO: stored_at の昇順で最古を捨てる。容量超過は通常 1 件ずつなのでループは 1 回回るのが基本。
        while entries.count > Self.capacity {
            if let oldestKey = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
                entries.removeValue(forKey: oldestKey)
            } else {
                break
            }
        }
    }
}
