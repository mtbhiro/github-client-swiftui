# テスト周りの落とし穴

## `URLSessionHttpClientTests` を `@Suite(.serialized)` で逐次実行している

### 症状

`URLSessionHttpClientTests` を Swift Testing デフォルトの並列実行で走らせると、複数テストが同時に動いた際に以下のいずれかが起きる:

- 期待した stub と異なるレスポンスが返ってきて assertion が失敗する（例: 別テスト用の `403 / 33 bytes` が読まれる）
- `Crash: github-client-swiftui at outlined consume of Data._Representation` で abort する

### 原因

テスト用の `StubURLProtocol` (`URLSessionHttpClientTests.swift` 末尾) が `nonisolated(unsafe) static var` でレスポンス情報（`stubbedData` / `stubbedStatusCode` / `stubbedError` / `stubbedDelay` / `onRequest`）をプロセス全体で共有している。Swift Testing は同一 suite 内のテストを並列実行するため、複数テストが同時に static state を読み書きしてレースが発生する。

`Data` の COW 内部表現が破壊レベルで壊れたケースが `Data._Representation` クラッシュ。壊れずに値だけ混線したケースが「stub が他テストの値を返す」現象。

### 暫定対応（現状）

`@Suite(.serialized)` を付けて URLSessionHttpClientTests を逐次実行している。10 件程度なので体感差は小さい。

### 本来あるべき設計

stub state を **テストインスタンスごと**に持つ形に作り替える。具体案:

- `StubURLProtocol` から static state を撤廃し、`Synchronization.Mutex` で守られた global `[Key: StubResponder]` map を介してインスタンス単位で responder を解決する
- テストごとに固有のホスト（例: `https://test-{UUID}.invalid/...`）を使い、`startLoading()` 内では `request.url?.host` をキーに responder を取得
- production の `ApiHost` を DI 化し、テストではテスト専用ホストに差し替える

これをやれば `.serialized` を外しても動く。`MockGithubRepoRepository` の `@unchecked Sendable` も同様の問題を抱えており、合わせて見直す価値がある（プロジェクトポリシーは `@unchecked Sendable` 禁止）。

### 一次ソース

- [Swift Testing — `Suite`](https://developer.apple.com/documentation/testing/suite) — Suite 内テストはデフォルトで並列実行される
- [Swift Testing — `Trait/serialized`](https://developer.apple.com/documentation/testing/trait/serialized) — `.serialized` で逐次実行を強制
- [Swift Evolution SE-0433 — Synchronous Mutual Exclusion Lock](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0433-mutex.md) — `Synchronization.Mutex` の導入提案

## `Task.sleep` で完了を待つテストが並列度で破綻する

### 症状

`@MainActor` な Observable Model が内部 `Task` を貼って結果を反映する設計（`fireSearch` / `loadNextPageIfNeeded` など）に対し、テスト側が「経過時間で完了を待つ」ヘルパで状態を確認していると、テスト数が一定数を超えた途端に並列実行で flaky になる。

```swift
private func waitTick(_ ms: Int = 50) async {
    try? await Task.sleep(for: .milliseconds(ms))
}

@Test func networkFailure_transitionsToErrorNetwork() async {
    let (model, _) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
    model.query = "swift"
    await waitTick()              // 50ms 待てば終わる前提
    #expect(model.phase == .errorNetwork)   // 並列度が上がると `.loading` のまま落ちる
}
```

典型的な失敗ログ:

```
Expectation failed: (model.phase → .loading) == .errorNetwork
Issue recorded: Expected loaded phase
Expectation failed: mock.searchCallCount == baseline + 1
```

### 原因

1. テスト Mock (`MockGithubRepoRepository`) が **actor**。`await mock.searchRepositories(...)` のたびに **MainActor → mock executor → MainActor** で 2 回 hop する。
2. Model 内の `Task { [weak self] in ... }` は `@MainActor` を継承して MainActor 上で順番待ちする。
3. テスト本体も `@MainActor struct`。Swift Testing は同一 Suite 内のテストをデフォルトで並列実行するが、**MainActor の executor は 1 本**しか無いので、並列に動く全 `@Test` Task が MainActor キューを取り合う。
4. テスト A の `await waitTick(50ms)` 中、テスト B 〜 F の `await waitTick` / `await #expect` / `await mock.setSearchResult` が MainActor キューに割り込み、テスト A の内部 Task の順番がなかなか回ってこない。
5. 50ms 経って waitTick から戻った瞬間に状態を assert → まだ `.loading` のまま → 失敗。

つまり「50ms 待てば終わる」は **MainActor キューの輻輳に依存する仮定**で、テスト数が増えると簡単に破綻する。`waitTick(200)` などに伸ばすのは対症療法（さらに並列度が上がればまた破綻する）。

### Apple 公式の推奨パターン

[Testing asynchronous code](https://developer.apple.com/documentation/testing/testing-asynchronous-code) は明確に次の 2 つを推奨している（sleep ベース polling は推奨しない）:

1. **直接 `await` できるなら直接 `await` する**
2. **`await` できない（event handler / delegate callback など）なら [`Confirmation`](https://developer.apple.com/documentation/testing/confirmation) を使う**。`expectedCount` で期待発生回数を宣言し、テストフレームワークが内部で待つ。

### `@Suite(.serialized)` を貼る前に検討すべき設計

`.serialized` は最終手段。**先に下記の順で検討**する:

1. **「完了そのもの」を await できる経路を作る**
   - Model に **最新の inflight task を読める read-only プロパティ**（`var inFlightTask: Task<Void, Never>? { currentTask }`）を生やす。テスト側は `await model.inFlightTask?.value` で待つ。
   - これで `waitTick(50ms)` を「経過時間を仮定しない待機」に置き換えられる。並列度がどれだけ上がっても安定する。
2. **`Confirmation` を使う**
   - Model 内のイベント（リクエスト発火・状態遷移）にフックを差し、`await confirmation { ... }` で「N 回起きたら閉じる」を宣言する。`await` できない callback 経由の状態変化を待つときの定石。
3. **テスト固有の独立リソースを使う**
   - `UserDefaults(suiteName: "...\(UUID().uuidString)")` のように **テストごとに固有のスロット**を切る。「テスト同士が共有状態を持たない」設計に直すと、並列実行で踏むレースの大半が消える。
4. **Mock を nonisolated + ロック化する**
   - actor hop を消して MainActor で同期完結させる。ただし「`waitTick` で待つ前提」自体は残るので、これだけでは本質解決にならない（1 と組み合わせる）。
5. **`@Suite(.serialized)` で逐次化する**（**ここまで来て初めて検討**）
   - テスト実行時間が伸びる + 「公式パターンを使っていない」状態が残ることを受け入れる場合のみ。`URLSessionHttpClientTests` の `StubURLProtocol` のように、static state の根本書き換えに大コストが要るケースで暫定的に使う。

「何も起きないこと」を確認するテスト（debounce 中の API 未発火など、本質的に時間経過を見るもの）に限っては `Task.sleep` ベースの待機が妥当。**判断軸は「待ちたいのは完了か、それとも時間経過か」**。

### 採用した設計（実例）

`RepositorySearchModel` に次を追加:

```swift
@Observable
final class RepositorySearchModel {
    var inFlightTask: Task<Void, Never>? { currentTask }
    private var currentTask: Task<Void, Never>?
    // ...
}
```

テスト側のヘルパ:

```swift
private func waitForInflight(_ model: RepositorySearchModel) async {
    await model.inFlightTask?.value
}

@Test func networkFailure_transitionsToErrorNetwork() async {
    let (model, _) = makeSUT(searchResult: .failure(URLError(.notConnectedToInternet)))
    model.query = "swift"
    await waitForInflight(model)    // 完了そのものを待つ
    #expect(model.phase == .errorNetwork)
}
```

これで `@Suite(.serialized)` を撤去でき、99 件のテストが並列実行で安定して通るようになった。

### 一次ソース

- [Swift Testing — Testing asynchronous code](https://developer.apple.com/documentation/testing/testing-asynchronous-code) — `await` と `Confirmation` の公式推奨
- [Swift Testing — `Confirmation`](https://developer.apple.com/documentation/testing/confirmation) — 「N 回起きたら閉じる」を宣言する API
- [Swift Testing — Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization) — 並列実行とその無効化
- Swift Concurrency: `Task.value` で Task の完了を待つ（`Task<Success, Failure>` の `.value`）
