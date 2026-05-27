# HTTP ヘッダの case-insensitive 処理の統一

## ステータス: 未着手

## 概要

HTTP レスポンスヘッダの case-insensitive lookup が複数箇所で独立に実装されている。HTTP/1.1 の仕様上ヘッダ名は case-insensitive だが、`Dictionary` のキーは case-sensitive なので、各箇所でアドホックに対処している状態。

## 該当箇所

### RateLimitObserver.swift:15

```swift
let limitString = headers["X-RateLimit-Limit"] ?? headers["x-ratelimit-limit"]
let remainingString = headers["X-RateLimit-Remaining"] ?? headers["x-ratelimit-remaining"]
```

2 パターンのみチェック。`X-RATELIMIT-LIMIT` のような形式には対応しない。

### RepositorySearchErrorMapper.swift:64-68

```swift
private static func headerValue(_ headers: [String: String], name: String) -> String? {
    if let exact = headers[name] { return exact }
    let lowered = name.lowercased()
    for (key, value) in headers where key.lowercased() == lowered {
        return value
    }
    return nil
}
```

全キーを小文字比較しており網羅的だが、`O(n)` のリニアサーチ。

## 改善案

### 案 A: `URLSessionHttpClient.headerMap` で小文字正規化

レスポンスヘッダを辞書に変換する時点で全キーを小文字にする。

```swift
// URLSessionHttpClient.swift
private static func headerMap(from response: HTTPURLResponse) -> [String: String] {
    var map: [String: String] = [:]
    for (key, value) in response.allHeaderFields {
        guard let keyString = key as? String, let valueString = value as? String else { continue }
        map[keyString.lowercased()] = valueString  // 正規化
    }
    return map
}
```

使用側は `headers["x-ratelimit-limit"]` で統一アクセスできる。

### 案 B: case-insensitive な Dictionary wrapper

```swift
struct CaseInsensitiveHeaders {
    private var storage: [String: String]
    
    subscript(_ key: String) -> String? {
        storage[key.lowercased()]
    }
}
```

## 影響範囲

- `Common/Networking/URLSessionHttpClient.swift`
- `Common/Auth/RateLimitObserver.swift`
- `Features/RepositorySearch/Model/RepositorySearchError.swift`
- `Common/Auth/AuthenticatedHttpClient.swift`
- 関連テスト（ヘッダのキー形式が変わるため）
