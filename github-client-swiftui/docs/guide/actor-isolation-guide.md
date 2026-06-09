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

## `struct` と `nonisolated struct` — 宣言から読み取れること

このプロジェクトでは `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` を設定しているため、`struct Foo` と `nonisolated struct Foo` は本質的に異なる宣言になる。

### コードレビューでの読み取り方

| 宣言 | 実際の意味 | レビュアーの解釈 |
|---|---|---|
| `struct Foo` | `@MainActor struct Foo` | 「UI 層に属する型」または「isolation を意識せず書かれた可能性がある」 |
| `nonisolated struct Foo` | actor 非依存の型 | 「意図的に UI から独立させた型。ネットワーク・データ変換・ドメインロジック層の型」 |

`nonisolated` の有無は単なるコンパイラ指示ではなく、**その型がアーキテクチャのどの層に属するかの宣言**として機能する。

### レビューで確認すべきこと

- **DTO / ドメインモデルに `nonisolated` がない** → 付け忘れの可能性が高い。バックグラウンドでのデコード時に不必要な `await` が発生する。
- **UI 状態を持つ型に `nonisolated` がある** → View から `@Observable` として使う型なら、デフォルトの `@MainActor` のままが正しい。
- **`nonisolated struct` に `@MainActor` なプロパティが混在している** → 設計が中途半端。層の分離を見直す。

### `await` が必要になる仕組み

`await` が必要になる理由は2つある:

1. **中断（suspend）する可能性がある** — ネットワーク通信、`Task.sleep` など、結果が返るまで待つ必要がある処理。
2. **actor 境界をまたぐ** — 現在の actor とは別の actor に隔離された型やメソッドを呼ぶとき、その actor のキューに並んで順番を待つ必要がある。

`nonisolated struct` のプロパティアクセスやイニシャライザに `await` が不要なのは、この**両方の理由がない**から:

- ただのメモリ上の値操作なので中断しない
- どの actor にも属さないので境界が存在しない

```swift
// @MainActor struct（デフォルト）の場合
struct UserInfo {
    var name: String
}

nonisolated func processInBackground() async {
    // バックグラウンドにいる → MainActor に切り替える必要がある → await 必須
    let user = await UserInfo(name: "Alice")
    let n = await user.name
}

// nonisolated struct の場合
nonisolated struct UserInfo {
    var name: String
}

nonisolated func processInBackground() async {
    // actor 境界がない → スレッド切り替え不要 → await 不要
    let user = UserInfo(name: "Alice")
    let n = user.name
}
```

### MainActor 上の suspend とメインスレッドの関係

`await` で suspend したとき、MainActor のメインスレッドは**解放される**。UI イベントループは回り続け、タップ・スクロール・アニメーション等が処理できる。これが `async/await` の核心的なメリット。

```swift
@MainActor
func fetchData() async {
    // ① メインスレッドで実行
    let data = await api.fetch()
    // ↑ suspend: メインスレッドを手放す → UI は固まらない
    // ② レスポンスが返ったらメインスレッドに戻って再開
    self.items = data
}
```

ただし、**suspend の前後でメインスレッド上で実行される同期コード自体が重ければ、その間は UI が固まる**。`await` が守ってくれるのは「I/O 待ちの間」だけ。

```swift
@MainActor
func processData() async {
    let data = await api.fetch()       // ← suspend、UI 固まらない
    let result = heavyComputation(data) // ← メインスレッド上で3秒 → UI 固まる
    self.items = result
}
```

重い CPU 処理は MainActor の外に出す:

```swift
@MainActor
func processData() async {
    let data = await api.fetch()
    let result = await Task.detached {
        heavyComputation(data)          // バックグラウンドスレッドで実行
    }.value                             // suspend、UI 固まらない
    self.items = result                 // メインスレッドで一瞬だけ代入
}
```

| 状況 | メインスレッド | UI |
|---|---|---|
| `await` で suspend 中 | 手放す（他の処理が走れる） | 固まらない |
| suspend 後の同期処理が軽い | 一瞬だけ占有 | 問題なし |
| suspend 後の同期処理が重い | 占有したまま | 固まる |

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
