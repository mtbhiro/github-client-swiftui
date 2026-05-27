# SearchRoute / BookmarksRoute の重複解消

## ステータス: 未着手

## 概要

`AppRoute.swift` の `SearchRoute` と `BookmarksRoute` が完全に同一の case を持っている。Issue 詳細にコメント遷移を追加する場合など、2 箇所を同時修正する必要があり、DRY 原則に反する。

## 現状のコード

```swift
// AppRoute.swift
enum SearchRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}

enum BookmarksRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}
```

## 改善案

共通の `ContentRoute` を定義し、タブごとの型安全性が必要なら newtype wrapper で包む。

```swift
enum ContentRoute: Hashable {
    case repositoryDetail(GitHubRepoFullName)
    case issueList(GitHubRepoFullName)
    case issueDetail(GitHubRepoFullName, number: Int)
}
```

`navigationDestination(for:)` のルーティングテーブルも 1 箇所に集約できる。

## 影響範囲

- `AppRoute.swift`
- `RootView.swift` / `RepositorySearchView.swift` / `BookmarkListView.swift` の `navigationDestination`
- `AppCoordinator.swift` の path プロパティ型
- `DeepLink.swift` の `searchPath`
- 関連テスト

## 対応方針

- `navigation-guide.md` の設計方針と整合を取りながら進める
- `AppCoordinator` の path 配列の型をどうするか（`[ContentRoute]` に統一 or タブごとの wrapper）を先に決める
