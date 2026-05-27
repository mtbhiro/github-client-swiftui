# ページネーション定数の集約

## ステータス: 未着手

## 概要

ページネーションの `perPage = 30` が複数の Model にハードコードされている。変更時に漏れが生じるリスクがある。

## 該当箇所

- `RepositorySearchModel.swift:58` — `static let perPage = 30`
- `IssueListModel.swift:28` — `static let perPage = 30`
- `GithubRepoRepository.swift:34` — `URLQueryItem(name: "per_page", value: "30")` （リテラル）
- `GithubRepoRepository.swift:65` — 同上
- `GithubRepoRepository.swift:80` — 同上

## 改善案

共通定数として 1 箇所で定義する。

```swift
// Common/Constants/PaginationConstants.swift
enum PaginationConstants {
    static let itemsPerPage = 30
}
```

Repository 層でも Model 層でもこの定数を参照する。

## 影響範囲

- `Common/Repository/GithubRepoRepository.swift`
- `Features/RepositorySearch/RepositorySearchModel.swift`
- `Features/IssueList/IssueListModel.swift`
- 関連テスト
