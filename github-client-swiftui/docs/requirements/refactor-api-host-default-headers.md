# ApiHost.defaultHeaders の重複 case 解消

## ステータス: 未着手

## 概要

`HttpClient.swift` の `ApiHost.defaultHeaders` で、`switch` の全 case が同一の値を返している。意図的に将来の拡張ポイントとして分けているなら問題ないが、現時点では無意味な分岐。

## 現状のコード

```swift
// HttpClient.swift:34-41
var defaultHeaders: [String: String] {
    switch self {
    case .github:
        ["Accept": "application/vnd.github.v3+json"]
    case .custom:
        ["Accept": "application/vnd.github.v3+json"]  // 全く同じ
    }
}
```

## 改善案

case を分ける意図がないなら単純に統一する。

```swift
var defaultHeaders: [String: String] {
    ["Accept": "application/vnd.github.v3+json"]
}
```

`.custom` ホストにはデフォルトヘッダを付けたくないケースが将来ありうるなら、その時に分岐を入れる（YAGNI 原則）。

## 影響範囲

- `Common/Networking/HttpClient.swift`
- 既存テストへの影響なし
