# ネットワークタイムアウトの設定

## ステータス: 未着手

## 概要

`URLSessionHttpClient` が `URLSession.shared` をそのまま使っており、タイムアウトが OS デフォルト（60 秒）のまま。モバイルアプリでは 15-30 秒が一般的。低速回線でユーザーが長時間待たされるリスクがある。

## 現状のコード

```swift
// URLSessionHttpClient.swift:9
init(
    session: URLSession = .shared,
    decoder: JSONDecoder = JSONDecoder()
) {
    self.session = session
    self.decoder = decoder
}
```

## 改善案

専用の `URLSessionConfiguration` を作成してタイムアウトを設定する。

```swift
static func makeDefaultSession() -> URLSession {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15    // リクエスト開始から応答まで
    config.timeoutIntervalForResource = 30   // リソース全体の転送完了まで
    return URLSession(configuration: config)
}
```

`AuthStack.makeProduction()` でこの session を `URLSessionHttpClient` に渡す。テスト時は引き続き `StubURLProtocol` を使った session を注入する。

## 影響範囲

- `Common/Networking/URLSessionHttpClient.swift`
- `github_client_swiftuiApp.swift` の `AuthStack.makeProduction()`
- テストは `StubURLProtocol` 経由なので影響なし
