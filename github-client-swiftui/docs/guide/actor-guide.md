# actor ガイド

Swift Concurrency の `actor` を「いつ・なぜ・どう使うか」をプロジェクトの実例に紐づけて整理する。
`@MainActor` / `nonisolated` の使い分けは [actor-isolation-guide.md](actor-isolation-guide.md)、`Sendable` 適合の判断は [sendable-guide.md](sendable-guide.md) を参照すること。本書はそれらの後段で、**独自に actor 型を定義するときの判断材料**に絞る。

## 1. actor とは何か

`actor` は **「内部の可変状態を、同時に 1 つの Task しか触らないことを言語機構で保証する型」**。Swift Concurrency が提供する 3 つ目の参照型（`class` / `@MainActor class` / `actor`）。

```swift
actor Counter {
    private var value = 0
    func increment() { value += 1 }
    func current() -> Int { value }
}

let c = Counter()
await c.increment()           // actor 外からは await が必須
let v = await c.current()
```

### actor が保証するもの

- **データ競合 (data race) を構造的に発生させない**。複数 Task が同時に actor のメソッドを呼んでも、actor の executor 上で逐次化される。
- **`Sendable` 適合が自動で得られる**。actor は本体が isolated なので、`@unchecked Sendable` のような抜け道なしに Sendable になる。

### actor が保証しないもの

- **順序保証はない**。actor は「同時実行しない」だけで、「呼び出し順に実行する」とは限らない。
- **`await` を挟むメソッドの不変条件は崩れる**（後述の reentrancy）。

## 2. actor / class / @MainActor class の使い分け

| 型 | 隔離 | Sendable | 主な用途 |
|---|---|---|---|
| `nonisolated struct` | なし | 自動（値型） | DTO・ドメインモデル・純粋関数 |
| `nonisolated final class` | なし | 全プロパティ不変なら自動 | プロトコル実装で状態を持たない型 |
| `@MainActor class` | MainActor | 自動 | UI 関連の状態（Observable Model など） |
| `actor` | 専用 executor | 自動 | UI から独立した「共有可変状態」 |
| `@unchecked Sendable class` | なし | 自己責任 | **本プロジェクトでは使わない** |

「UI に関係する可変状態」は `@MainActor class` を選ぶ（このプロジェクトでは `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` でデフォルト）。
「UI に関係しない可変状態」を「複数 Task から触る」可能性があるときに初めて `actor` の出番。

## 3. actor をいつ使うか — 判断フロー

```
状態を持つか？
├─ No → struct / nonisolated enum / 関数で十分
└─ Yes
   └─ UI 関連の状態か？
      ├─ Yes → @MainActor class（プロジェクト規約）
      └─ No
         └─ 複数 Task から同時に触る可能性があるか？
            ├─ No → nonisolated final class（全プロパティ let）か struct
            └─ Yes
               └─ actor を使う ★
```

「複数 Task から同時に触る可能性があるか」が要。**そもそも 1 つの Task からしか触らないなら、actor のコストを払う意味はない**。

### actor が向いている典型例

- **キャッシュ / メモ化テーブル**（`URLCache` の自前版、デコード結果のキャッシュなど）
- **接続プール / レート制限器**（複数 Task が同時に消費しに来る）
- **テスト用 Mock の中で「呼び出し回数」「最後の引数」を記録するもの**（本プロジェクトの `MockGithubRepoRepository` がこれ）
- **永続ストレージのライトバックバッファ**

### actor が **不向き** な典型例

- **UI 状態** → `@MainActor` のほうが SwiftUI の更新モデルと噛み合う
- **不変データ + 純粋関数の集合** → `struct` で十分（actor のオーバーヘッドが無駄）
- **1 つの Task からしか触らない一時バッファ** → ローカル変数で済む

## 4. メリット（採用する理由）

### 4.1 `@unchecked Sendable` を排除できる

`@unchecked` は **「Sendable のコンパイラチェックを無効化する」**宣言で、`.claude/rules/swift-coding.md §1 / §9` で禁止している抜け道。
actor はチェックを無効化せず、言語機構で本物の安全性を提供する。

```swift
// Before: 規約違反
nonisolated final class MockGithubRepoRepository: GithubRepoRepositoryProtocol, @unchecked Sendable {
    var searchResult: Result<..., Error>   // ← var なのに Sendable を宣言、保証はゼロ
    var searchCallCount = 0
    ...
}

// After: actor 化で @unchecked を撤去
actor MockGithubRepoRepository: GithubRepoRepositoryProtocol {
    var searchResult: Result<..., Error>
    var searchCallCount = 0
    ...
}
```

### 4.2 データ競合の実害もまとめて消える

`@unchecked Sendable` は「コンパイラを黙らせる」だけなので、実際にレースが起きうる構造だった。例:

```swift
mock.searchResult = .failure(URLError(...))   // テストスレッド (MainActor)
model.loadNextPageIfNeeded()                  // Task 内で mock.searchResult を読む
```

両方向のアクセスが同時に走ると **理論上のデータ競合**。actor 化するとアクセスがすべて actor の executor 上で逐次化されるので、この race が構造的に発生しなくなる。`URLSessionHttpClientTests` が `@Suite(.serialized)` で誤魔化していた類のレースも、actor 化すれば不要になる。

### 4.3 `Sendable` 適合のためのボイラープレートが減る

`nonisolated final class` で Sendable を満たすには「全プロパティを `let` にする」「`OSAllocatedUnfairLock` で守る」など追加コードが要る。actor は宣言だけで Sendable が得られる。

## 5. デメリット（採用するときに払うコスト）

### 5.1 呼び出し側に `await` が伝播する（function coloring）

actor の外からの全アクセスが `async` になる。

```swift
// Before
#expect(mock.searchCallCount == 0)
mock.searchResult = .failure(...)

// After
await #expect(mock.searchCallCount == 0)
await mock.setSearchResult(.failure(...))
```

一度 `async` が現れると呼び出し側にも `async` が要求され、感染していく（"function coloring" 問題）。**同期コンテキストからは触れない**点に注意。

### 5.2 プロパティ直接代入ができず、setter メソッドが必要

actor 外から `mock.searchResult = ...` は禁止される。`var` プロパティへの外部 set は actor 隔離違反。

```swift
actor MockGithubRepoRepository: GithubRepoRepositoryProtocol {
    var searchResult: Result<..., Error>

    // 外部から書くにはメソッド経由が必須
    func setSearchResult(_ result: Result<..., Error>) {
        searchResult = result
    }
}
```

`MockGithubRepoRepository` では `setSearchResult` / `setSearchResultHandler` / `setIssuesResult` ... を 6 個追加する必要があった。書き換え自由度が高い Mock とは特に相性が悪いボイラープレート。

### 5.3 reentrancy の罠

**「actor だから逐次実行」というのは半分しか正しくない**。actor のメソッドが `await` で suspend した瞬間、他の Task からの呼び出しを受け付ける。

```swift
actor MockGithubRepoRepository {
    var searchResult: Result<..., Error>

    func searchRepositories(...) async throws -> ... {
        searchCallCount += 1
        try await Task.sleep(for: .milliseconds(100)) // ← suspend
        // ↑ この間に別 Task から setSearchResult されている可能性あり
        return try searchResult.get()
    }
}
```

actor は **データ競合を防ぐ** が **順序保証はしない**。`await` を挟むメソッドの前後で actor 内の状態が変わっていることがあり得るので、不変条件は明示的に書き直す必要がある。
回避策: `await` を挟む前にローカルにスナップショットを取る、`await` の前後で状態を読み直す、`@_unsafeInheritExecutor` や `nonisolated` の活用、など。

### 5.4 executor hop の実行コスト

actor 境界をまたぐ `await` は executor の hop を伴う（=スレッド切替の可能性）。
本プロジェクトの実プロダクト `GithubRepoRepository` は `nonisolated struct` で hop なし。一方 Mock は `actor` なので、MainActor → mock actor → MainActor の往復が発生する。

```
RepositorySearchModel (@MainActor)
    → await mock.searchRepositories(...)   // hop: MainActor → mock の executor
        await session.data(...)             // 内部の async I/O
    ← return                                // hop: mock の executor → MainActor
```

テスト用なら無視できるが、ホットパスで多用すると無視できなくなる。

### 5.5 テストとプロダクトで実行モデルがずれる

上記 5.4 の系として、Mock を actor、プロダクトを nonisolated struct で書くと **実行モデルがズレる**。
通常は問題にならないが、「テストは通るがプロダクトでだけ起きる/起きない」種類のバグの温床になりうるので頭の片隅に置いておく。

### 5.6 `init` の特殊扱い

actor の `init` は `nonisolated` 扱いで、`self.foo = ...` は同期で書けるが、init 内でメソッド呼び出しをすると `await` が要ることがある。
init で複雑な初期化をしたいときは制約が出る。

### 5.7 同期的な等価判定が書けない

actor のプロパティ読みに `await` が要るため、`Equatable` / `Hashable` を素直に実装できない。Mock を集合に入れたいような場面では制約になる。

## 6. ケーススタディ: `MockGithubRepoRepository` を actor 化した経緯

レビューで「`@unchecked Sendable` がプロジェクト規約 (`.claude/rules/swift-coding.md §1 / §9`) に違反している」と指摘され、解消方法を検討した。

### 候補と却下理由

| 候補 | 結果 | 理由 |
|---|---|---|
| `@MainActor final class` | ✗ | `GithubRepoRepositoryProtocol` のメソッドが `nonisolated async` で、`@MainActor` 型では適合できない。Protocol を `@MainActor` にすると実プロダクトの `GithubRepoRepository` が MainActor 拘束されてしまう |
| `OSAllocatedUnfairLock` で守る | △ | `nonisolated` のまま Sendable を満たせるが、Lock ベースは書き味が悪く、テスト Mock のためには重い |
| `Mutex` (Swift 6) | ✗ | iOS 18+ が必要。本プロジェクトは iOS 17 ターゲット |
| **`actor` 化** | ◯ | 規約適合・本物のデータ競合排除・protocol の `nonisolated async` 要件適合を全部満たす |

### actor 化の代償

- テストの記述コスト: `mock.searchResult = X` → `await mock.setSearchResult(X)` の書き換えが多数発生。
- Mock に 6 個の setter メソッドを追加するボイラープレート。
- テスト Mock とプロダクト実装で実行モデルがズレる（プロダクトは `nonisolated struct`）。

これらは「Mock の内部に `await` を挟むメソッドが無い」「テストはもともと `@MainActor struct` で `async` 文脈にある」ことから、reentrancy の罠と function coloring のコストを実害として受けない、と判断した上で許容している。

### 将来の見直し基準

次のいずれかが当てはまったら、`OSAllocatedUnfairLock` ベースの `nonisolated final class` に乗り換えるのが妥当:

1. テストコードの `await` が読みづらく、Mock 操作で本質が見えなくなったとき
2. 同期コンテキスト（同期テスト、computed property の中など）から Mock を触りたいとき
3. Mock の内部に `await` を挟むメソッドが増えて reentrancy リスクが上がったとき

## 7. actor を使うときのチェックリスト

新規に `actor` 型を導入するときは以下を確認する:

- [ ] **複数 Task から同時に触る必要が本当にあるか?** 1 Task からしか触らないなら不要。
- [ ] **UI 状態ではないか?** UI 状態なら `@MainActor class` を選ぶ。
- [ ] **actor 内のメソッドで `await` を挟むか?** 挟むなら reentrancy を意識し、`await` 前後で状態を読み直す設計にする。
- [ ] **呼び出し側のコンテキストは async か?** 同期文脈から触りたいなら actor は不適。
- [ ] **executor hop のコストが問題になるホットパスか?** ホットパスなら計測した上で採用判断する。
- [ ] **`Equatable` / `Hashable` を必要としないか?** 必要なら actor 以外を検討。

## 8. 困ったときの参照先

- 本プロジェクトの規約: `.claude/rules/swift-coding.md`（`@unchecked Sendable` 禁止、Mock パターン）
- [actor-isolation-guide.md](actor-isolation-guide.md): `@MainActor` / `nonisolated` の取り回し
- [sendable-guide.md](sendable-guide.md): Sendable 適合判断
- [task-cancellation-guide.md](task-cancellation-guide.md): Task キャンセルと actor の関係
- Apple 公式: `mcp__cupertino__search_concurrency` で `actor` / `isolation` / `reentrancy` をひく
- 落とし穴索引: `docs/pitfalls/README.md`（特に `testing.md` の stub race の項）
