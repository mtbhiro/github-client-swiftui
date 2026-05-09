# Task キャンセルガイド

## 前提: キャンセルは協調的

Swift Concurrency のキャンセルはフラグを立てるだけで、**何かがチェックしない限り何も起こらない**（SE-0304）。

> "cancellation has no effect at all unless something checks for cancellation"

## キャンセルフラグの仕組み

Swift Concurrency のランタイムは、各スレッドで現在実行中の Task への参照を保持している。`Task.isCancelled`、`Task.checkCancellation()`、`withTaskCancellationHandler` はすべてこの仕組みで「自分がどの Task で動いているか」を暗黙的に知っている。明示的に Task を渡す必要はない。

```swift
// これらは全部「今自分が走っている Task」を暗黙的に参照する
Task.isCancelled              // 現在の Task のフラグを読む
try Task.checkCancellation()  // 現在の Task のフラグを読んで throw
Task.currentPriority          // 現在の Task の優先度を読む
```

## キャンセルをチェックする2つの方法

### 1. ポーリング型: `isCancelled` / `checkCancellation()`

同期コードの途中で「今キャンセルされてる？」を確認する。

```swift
for item in largeCollection {
    try Task.checkCancellation()
    process(item)
}
```

### 2. コールバック型: `withTaskCancellationHandler`

`Task.cancel()` された**瞬間**にコールバックが発火する。`await` でブロック中の処理を外から中断させたいときに使う。

```swift
return try await withTaskCancellationHandler {
    return try await someLegacyCallback()
} onCancel: {
    // Task.cancel() された瞬間にここが呼ばれる（別スレッドから即座に）
    legacyHandle.abort()
}
```

キャンセル非対応のレガシー API をラップするときに自分で書く。下位の API が既にキャンセル対応済み（`URLSession`、`Task.sleep` など）なら `try await` するだけで十分。

## URLSession でのキャンセル伝播の流れ

`URLSession.data(for:)` は内部で `withTaskCancellationHandler` を使っている。`Task.cancel()` が呼ばれると以下の流れで処理が中断される：

```
Task.cancel() が呼ばれる
    ↓
Task 全体にキャンセルフラグが立つ
    ↓
withTaskCancellationHandler の onCancel が即座に発火
    ↓
内部で保持している URLSessionDataTask.cancel() を呼ぶ
    ↓
進行中のネットワーク I/O が中断される
    ↓
URLError(.cancelled) が throw される
```

レスポンスの完了を待つのではなく、**ネットワーク接続自体が即座に中断される**。

### URLError と CancellationError の変換

`URLSession` が投げるのは `URLError(.cancelled)` であり、Swift Concurrency の `CancellationError` ではない。このプロジェクトでは `URLSessionHttpClient` で変換している：

```swift
} catch let error as URLError {
    if error.code == .cancelled {
        throw CancellationError()  // URLError → CancellationError に変換
    }
    throw HttpClientError.networkError(error)
}
```

この変換により、呼び出し側の Model は `catch is CancellationError` だけで統一的にキャンセルを処理できる。

### このプロジェクトでの具体的なキャンセルフロー

```
currentTask?.cancel()（例: 新しい検索クエリが入力された）
    ↓
Task 内で await 中の処理に伝播
    ├─ Task.sleep 中 → sleep が CancellationError を throw
    └─ session.data(for:) 中 → URLSessionDataTask.cancel() → URLError(.cancelled)
        → URLSessionHttpClient が CancellationError に変換して throw
    ↓
catch is CancellationError で捕まる（何もしない）
```

## チェックすべきタイミング

### 重い処理を始める「前」

リクエスト送信やファイル I/O など、コストの高い処理を開始する前にチェックする。既にキャンセルされているなら無駄な処理を避けられる。

```swift
func send<T: Decodable & Sendable>(_ request: HttpRequest) async throws -> T {
    let urlRequest = try buildURLRequest(from: request)
    try Task.checkCancellation()  // ← リクエスト開始前
    let (data, response) = try await session.data(for: urlRequest)
    // ...
}
```

## チェックが不要なタイミング

### await の「後」

`URLSession.data(for:)` のような I/O 関数は内部でキャンセルに応答し、キャンセル時にはエラーを投げる。`await` から返った時点でキャンセルチェックは済んでいるため、直後の `checkCancellation()` は冗長になる。

```swift
// ❌ await 後の checkCancellation は不要
let results = try await repository.searchRepositories(query: query, page: 1)
try Task.checkCancellation()
guard let self else { return }

// ✅ guard だけで十分
let results = try await repository.searchRepositories(query: query, page: 1)
guard let self else { return }
```

SE-0304 でも、ほとんどの関数では下位レベルの I/O 関数が内部でチェックしてくれるので十分とされている。

> "In most functions, it should be sufficient to rely on lower-level functions that can wait for a long time (for example, I/O functions or Task.value) to check for cancellation and abort early."

## checkCancellation() vs isCancelled

| 方法 | 用途 |
|---|---|
| `try Task.checkCancellation()` | キャンセル時に即座に `CancellationError` を投げて脱出したいとき |
| `Task.isCancelled` | キャンセル時にクリーンアップや部分結果の返却など、制御したい処理があるとき |

## このプロジェクトでの方針

- `URLSessionHttpClient` がリクエスト前に `checkCancellation()` でガードしているため、呼び出し側の Model では `await` 後のキャンセルチェックは不要。
- Model 層では `guard let self` や `Task.isCancelled` で状態更新をスキップすれば十分。
- `CancellationError` はユーザー向けエラーとして表示しない（`catch is CancellationError` で握りつぶす）。
