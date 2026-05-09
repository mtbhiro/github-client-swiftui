# NavigationStack の遷移設計ガイド

## 前提: このプロジェクトの方針

`NavigationStack(path:)` と `AppCoordinator` による一元管理を採用している。
遷移状態は `Hashable` な typed route の配列で保持し、タブごとに path を分離する。

## .navigationDestination はルーティングテーブル

`.navigationDestination(for: Route.self)` は「この画面から直接遷移する先」ではなく、**NavigationStack 全体のルーティングテーブル**として機能する。

```swift
NavigationStack(path: $coordinator.searchPath) {
    // ルートビュー
    .navigationDestination(for: SearchRoute.self) { route in
        switch route {
        case .repositoryDetail: ...  // 検索一覧から直接遷移
        case .issueList: ...         // リポジトリ詳細から遷移
        case .issueDetail: ...       // Issue 一覧から遷移
        }
    }
}
```

検索画面から直接遷移しない `.issueList` や `.issueDetail` がルートに含まれるのは正常。
path に push されたすべての route をこの1箇所で解決する必要があるため。

## tree-based との違い

| | stack-based (このプロジェクト) | tree-based (TCA 等) |
|---|---|---|
| ルート定義 | スタックのルートに全て集約 | 各画面が自分の子だけを持つ |
| 一元管理 | path 配列で容易 | ネストした state の構築が必要 |
| ディープリンク | path 配列を組むだけ | 入れ子の state 構築が煩雑 |

tree-based は各画面の責務が分離されるが、一元管理やディープリンクとの相性が悪い。
一元管理を前提とする場合、stack-based が適切な選択。

## ルート定義が肥大化した場合

画面数が増えたら、`switch` 内のビュー生成をファクトリメソッドに切り出して整理する。
ルーティングテーブルの集約構造自体は変えない。
