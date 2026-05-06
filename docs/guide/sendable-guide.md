# Sendable が必要になる理由と判断基準

## Sendable とは

`Sendable` は型のインスタンスが **actor の境界を越えて安全に渡せる**ことを表すプロトコル。関数の挙動には影響せず、型自体の安全性を保証する。

## いつ Sendable が必要になるか

**actor の isolation boundary を越えて値を渡すとき**に必要になる。

このプロジェクトでの具体例:

```swift
@MainActor @Observable
final class RepositorySearchModel {
    private let repository: RepositorySearchRepositoryProtocol

    func searchRepositories(query: String) async {
        // repository.searchRepositories() は nonisolated async
        // → MainActor の外で実行される
        // → repository が MainActor → nonisolated の境界を越える
        // → Sendable が必要
        let results = try await repository.searchRepositories(query: query, page: 1)
    }
}
```

## なぜこの因果関係になるのか

```
ネットワーク呼び出しが async
→ メインスレッドに縛りたくないのでメソッドを nonisolated にする
→ 呼び出し時に repository が MainActor → nonisolated の境界を越える
→ Sendable が必要
```

逆に言えば、async でなければ nonisolated にする動機がなく、`@MainActor` のまま同じ actor 上で完結するので Sendable は不要。

## Sendable に準拠できる条件

| 型 | 条件 |
|---|---|
| `struct` | 全ストアドプロパティが `Sendable` |
| `class` | `final` かつ全ストアドプロパティが不変(`let`)で `Sendable` |
| `actor` | 自動的に `Sendable` |
| `@unchecked Sendable` | コンパイラチェックを省略し自己責任で保証(ロック等) |

## プロトコルに Sendable をつける意味

```swift
nonisolated protocol RepositorySearchRepositoryProtocol: Sendable {
    func searchRepositories(query: String, page: Int) async throws -> [GitHubRepository]
}
```

プロトコルに `Sendable` をつけると、準拠するすべての型に上記の条件を強制する。プロトコルのメソッドが Sendable になるわけではない。

## nonisolated の粒度: 型 vs 関数

プロトコルのメソッドだけ `nonisolated` にしても目的は達成できるが、実用上は型全体を `nonisolated` にした方がよい。

```swift
// メソッドだけ nonisolated にする場合:
// プロトコル自体は @MainActor → 準拠する型の init も @MainActor
// → デフォルト引数は nonisolated で評価される
// → @MainActor な init をデフォルト引数に書くとエラー
// → 結局 init にも nonisolated が必要になる
// → 型全体を nonisolated にした方がすっきりする
```

詳細は [actor-isolation-guide.md](actor-isolation-guide.md) のデフォルト引数の節を参照。
