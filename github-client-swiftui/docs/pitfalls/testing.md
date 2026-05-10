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
