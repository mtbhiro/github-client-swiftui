import Foundation

/// テストで時刻を制御するための可変クロック。
/// MainActor 上のテスト内で `now` クロージャを `RepositorySearchCache(now:)` に注入する。
@MainActor
final class MutableClock {
    private var currentDate: Date

    init(currentDate: Date = Date(timeIntervalSince1970: 1_000_000)) {
        self.currentDate = currentDate
    }

    func now() -> Date { currentDate }

    func advance(seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }
}
