# navigationDestination ルーティングテーブルの抽出

## ステータス: 未着手

## 概要

`RepositorySearchView.swift:86-109` と `BookmarkListView.swift` で `.navigationDestination(for:)` のルーティングテーブルが重複している。`SearchRoute` と `BookmarksRoute` の重複解消（`refactor-route-duplication.md`）と合わせて、ルーティングを 1 箇所に集約すべき。

## 現状のコード

```swift
// RepositorySearchView.swift:86-109
.navigationDestination(for: SearchRoute.self) { route in
    switch route {
    case let .repositoryDetail(fullName):
        RepositoryDetailView(fullName: fullName, issueListRoute: SearchRoute.issueList(fullName), repository: repository)
    case let .issueList(fullName):
        IssueListView(fullName: fullName, issueDetailRoute: { number in SearchRoute.issueDetail(fullName, number: number) }, repository: repository)
    case let .issueDetail(fullName, number):
        IssueDetailView(fullName: fullName, issueNumber: number, repository: repository)
    }
}
```

`BookmarkListView` にも同等のルーティングがある（`BookmarksRoute` 版）。

## 改善案

Route → View の変換を共通の ViewModifier または ViewBuilder 関数に抽出する。

```swift
// 例: 共通 ViewBuilder
@ViewBuilder
func destination(for route: ContentRoute, repository: any GithubRepoRepositoryProtocol) -> some View {
    switch route {
    case let .repositoryDetail(fullName):
        RepositoryDetailView(...)
    case let .issueList(fullName):
        IssueListView(...)
    case let .issueDetail(fullName, number):
        IssueDetailView(...)
    }
}
```

## 前提タスク

- `refactor-route-duplication.md` で Route 型を統一してからのほうが自然

## 影響範囲

- `Features/RepositorySearch/RepositorySearchView.swift`
- `Features/Bookmark/BookmarkListView.swift`
- `Common/Navigation/` に共通ルーティング関数を追加
