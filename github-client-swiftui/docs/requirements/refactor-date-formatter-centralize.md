# DateFormatter の集約

## ステータス: 未着手

## 概要

`ISO8601DateFormatter` や `DateFormatter` が複数箇所で個別に生成されている。フォーマッタの生成コストは高く、同一設定のインスタンスが散在すると一貫性の維持も難しくなる。

## 該当箇所

- `GitHubRepoDetailDTO.swift:39` — `ISO8601DateFormatter()` を `toDomain()` 呼び出しごとに生成
- `GitHubIssueDetailDTO.swift` — 同上
- `RepositorySearchView.swift:304-312` — `static let rateLimitResetFormatter` (DateFormatter)
- `RepositorySearchFiltersView.swift` — DatePicker 関連のフォーマッタ

## 改善案

共通のフォーマッタを 1 箇所で定義する。

```swift
// Common/Formatting/DateFormatters.swift
enum DateFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    static let rateLimitReset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
```

`nonisolated` で定義し、`Sendable` な使い方に注意する。`ISO8601DateFormatter` は thread-safe なので static let で共有可能。`DateFormatter` は thread-safe ではないが、read-only で使う限り問題ない。

## 影響範囲

- 各 DTO ファイル
- `Features/RepositorySearch/RepositorySearchView.swift`
- 新規ファイル追加（`Common/Formatting/DateFormatters.swift`）
