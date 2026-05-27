# RepositorySearchModel の suppressQueryDidSet フラグ除去

## ステータス: 未着手

## 概要

`RepositorySearchModel.swift` で `query` プロパティの `didSet` 内から検索を発火しつつ、一部ケース（チップ削除時のキーワードクリアなど）では `suppressQueryDidSet` フラグで副作用を抑制している。状態遷移が `didSet` の有無に暗黙的に依存しており、将来の変更でバグが生まれやすい fragile な設計。

## 現状のコード

```swift
// RepositorySearchModel.swift:44-50
var query: String = "" {
    didSet {
        guard query != oldValue else { return }
        guard !suppressQueryDidSet else { return }
        onQueryChanged()
    }
}

private var suppressQueryDidSet = false

// L197-201
private func setQueryWithoutFiring(_ newValue: String) {
    suppressQueryDidSet = true
    query = newValue
    suppressQueryDidSet = false
}
```

## 改善案

`query` の `didSet` から副作用（検索発火）を除去し、検索発火を明示的なメソッド呼び出しに統一する。

View 側の `TextField` binding で `.onChange(of: model.query)` を使って検索を発火する形にすると、`suppressQueryDidSet` フラグが不要になる。

```swift
// Model 側: query は単なるプロパティ。副作用なし。
var query: String = ""

// View 側: 明示的に検索発火
TextField("リポジトリを検索", text: $model.query)
    .onChange(of: model.query) { _, newValue in
        model.onQueryChanged(newValue)
    }
```

あるいは Model 内で `setQuery(_:shouldFire:)` メソッドを用意する形でもよい。

## 影響範囲

- `RepositorySearchModel.swift`
- `RepositorySearchView.swift` の TextField binding
- `RepositorySearchModelTests.swift` / `RepositorySearchModelCacheTests.swift` / `RepositorySearchModelPersistenceTests.swift`
