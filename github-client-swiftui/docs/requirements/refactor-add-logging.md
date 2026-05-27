# 構造化ログの導入

## ステータス: 未着手

## 概要

現在のコードに `os_log` / `Logger` が一切なく、ネットワークエラー、デコード失敗、認証状態遷移、キャッシュヒット/ミスなどのイベントが追跡不可能。デバッグ時や将来的な品質監視のために、Apple の `os.Logger` を使った構造化ログを導入すべき。

## 導入すべき箇所と優先度

### 高優先度

1. **認証状態遷移** (`GitHubAuthState.swift`)
   - signedOut → signingIn → signedIn の遷移
   - 401 ハンドリング発火
   - Token 保存/読み込み/削除
2. **ネットワークエラー** (`URLSessionHttpClient.swift`)
   - HTTP エラーレスポンス（ステータスコード、URL）
   - デコード失敗（型名、URL）
   - タイムアウト
3. **レート制限** (`RateLimitObserver.swift`, `RepositorySearchErrorMapper.swift`)
   - 残りリクエスト数が閾値以下になったとき
   - 制限到達

### 中優先度

4. **キャッシュ** (`RepositorySearchCache.swift`)
   - ヒット/ミス（デバッグログ）
   - LRU 退避発生
5. **DTO 変換失敗**
   - `.distantPast` フォールバック発生時

## 実装方針

```swift
import os

extension Logger {
    static let auth = Logger(subsystem: "hiroc19.github-client-swiftui", category: "auth")
    static let network = Logger(subsystem: "hiroc19.github-client-swiftui", category: "network")
    static let cache = Logger(subsystem: "hiroc19.github-client-swiftui", category: "cache")
}
```

- `Logger.auth.info("Auth state: \(oldPhase) → \(newPhase)")` のように使う
- ログレベル: `debug`（キャッシュ）、`info`（状態遷移）、`error`（通信失敗）
- トークン等の機密情報は `\(token, privacy: .private)` で出力する

## 影響範囲

- 上記各ファイル（ログ出力の追加のみ、既存ロジックの変更なし）
- Logger 定義ファイルの新規作成（`Common/Logging/` など）
