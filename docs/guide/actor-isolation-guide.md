# MainActor と nonisolated の設計ガイド

## 前提: このプロジェクトの設定

Xcode 26 (Swift 6.2) で導入された `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` を有効にしている。
これにより、モジュール内のすべての型はデフォルトで `@MainActor` になる。

## nonisolated とは何か

「どのアクターにも隔離(isolate)されていない」という意味。
`@MainActor` や `actor` はデータを特定のスレッドに隔離して守る仕組みで、`nonisolated` はその隔離を受けないことを示す。
特定のスレッドを指定するのではなく、「アクターの保護対象ではない」という宣言。

## なぜ nonisolated を書く必要があるのか

デフォルトが `MainActor` なので、UI 層以外の型には明示的にオプトアウトが必要。

```
nonisolated なし → @MainActor（メインスレッドでしか使えない）
nonisolated あり → アクター非依存（どこからでも呼べる）
```

このプロジェクトでは以下の型に `nonisolated` を付けている:

- **ネットワーク層**: HttpClient, HttpRequest, URLSessionHttpClient など
- **データ層**: DTO, Mapper, Repository
- **ドメインモデル**: GitHubRepository, GitHubRepositoryOwner
- **サンプルデータの extension**: 別ファイルの extension はモジュールデフォルトに従うため明示が必要

## デフォルト引数と nonisolated の関係

`@MainActor` クラスの init であっても、デフォルト引数の式は nonisolated コンテキストで評価される（呼び出し側のコンテキストで評価されるため）。

```swift
@MainActor
final class RepositorySearchModel {
    init(
        // ← この式は nonisolated コンテキストで評価される
        repository: RepositorySearchRepositoryProtocol = RepositorySearchRepository(),
        debounceDuration: Duration = .milliseconds(300)
    ) {
        // ← ここは @MainActor コンテキスト
        self.repository = repository
    }
}
```

そのため、デフォルト引数で呼び出す型の init は nonisolated から呼べる必要がある。
`RepositorySearchRepository` が `nonisolated struct` なので問題なく動作する。

## デフォルトが MainActor になった背景

Apple の判断: 一般的な UI アプリのコードの大半は View から呼ばれる同期的なロジック（プロパティ読み書き、バリデーション、フォーマット変換など）で、結局 MainActor 上で動く必要がある。

本当に nonisolated であるべき層（ネットワーク、DB、デコード、画像処理）は型の数としては少数派、というのが Apple の見立て。

ただし Data 層が厚いアプリほど nonisolated が多くなるので、すべてのアーキテクチャに最適というわけではない。

## 従来のデフォルト（nonisolated）との対比

| デフォルト | UI 層 | データ層 |
|---|---|---|
| nonisolated（従来） | `@MainActor` を明示 | そのまま |
| MainActor（本プロジェクト） | そのまま | `nonisolated` を明示 |

どちらを選んでも片方に明示が必要。Apple は後者のほうが書く総量が少ないアプリが多いと判断した。

## 現在の状態

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` は Swift 6.2 の opt-in 機能
- Apple は将来的にこれをデフォルトにする方向で進めている
- Swift のデフォルトは現時点ではまだ nonisolated
