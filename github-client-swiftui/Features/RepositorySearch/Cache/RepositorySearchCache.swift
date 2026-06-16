import Foundation
import os
import SwiftUI

/// リポジトリ検索結果の短期メモリキャッシュ (PRD: repository-search-cache.md §5)。
/// 同期参照前提 (AC-1.1) のため、View Model と同じ MainActor 上で動く UI 状態の付属物として扱う。
/// TTL は設けず、容量 100 件の LRU 退避とプロセス終了 / Pull-to-refresh による明示破棄のみで失効する。
final class RepositorySearchCache {

    struct Key: Hashable, Sendable {
        let query: String
        let sort: RepositorySearchSort
        let page: Int
    }

    static let capacity = 100

    private var entries: [Key: RepositorySearchPageResult] = [:]
    /// 先頭が最も古くアクセスされたキー、末尾が最も新しい。`put` または `get` 成功で末尾に更新される。
    private var accessOrder: [Key] = []

    func get(_ key: Key) -> RepositorySearchPageResult? {
        guard let value = entries[key] else {
            Logger.cache.debug("Cache miss: page=\(key.page)")
            return nil
        }
        Logger.cache.debug("Cache hit: page=\(key.page)")
        touch(key)
        return value
    }

    func put(_ key: Key, value: RepositorySearchPageResult) {
        entries[key] = value
        touch(key)
        evictIfNeeded()
    }

    /// 指定したクエリ + ソートに紐づく全ページのエントリを破棄する (Pull-to-refresh で使用、AC-6.1)。
    func invalidate(query: String, sort: RepositorySearchSort) {
        let targets = entries.keys.filter { $0.query == query && $0.sort == sort }
        for key in targets {
            entries.removeValue(forKey: key)
        }
        accessOrder.removeAll { entries[$0] == nil }
    }

    private func touch(_ key: Key) {
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > Self.capacity, let oldest = accessOrder.first {
            Logger.cache.debug("LRU evict: page=\(oldest.page)")
            entries.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }
}

private struct RepositorySearchCacheEnvironmentKey: EnvironmentKey {
    static let defaultValue: RepositorySearchCache = {
        #if DEBUG
        return RepositorySearchCache()
        #else
        fatalError("searchCache environment key not injected")
        #endif
    }()
}

extension EnvironmentValues {
    var searchCache: RepositorySearchCache {
        get { self[RepositorySearchCacheEnvironmentKey.self] }
        set { self[RepositorySearchCacheEnvironmentKey.self] = newValue }
    }
}
