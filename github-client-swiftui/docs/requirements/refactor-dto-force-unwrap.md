# DTO の force unwrap 除去

## ステータス: 完了

## 概要

DTO の `toDomain()` メソッドで URL 文字列を `URL(string:)!` で強制アンラップしている箇所が複数ある。GitHub API が不正な URL を返した場合にアプリがクラッシュする。プロダクション品質のコードとしては防御的に処理すべき。

## 該当箇所

- `GitHubRepoDetailDTO.swift:47` — `URL(string: owner.htmlUrl)!`
- `GitHubRepoDetailDTO.swift:51` — `URL(string: htmlUrl)!`
- `GitHubIssueDetailDTO.swift` — 同様のパターン
- `HttpClient.swift:28` — `URL(string: "https://api.github.com")!`（static URL なのでリスクは低い）

## 改善案

### 案 A: `toDomain()` を `throws` にする

```swift
func toDomain() throws -> GitHubRepoDetail {
    guard let htmlUrl = URL(string: htmlUrl) else {
        throw DTOMappingError.invalidURL(field: "htmlUrl", value: htmlUrl)
    }
    // ...
}
```

Repository 層で catch してエラーに変換する。

### 案 B: Decodable の `init(from:)` 内で URL に変換する

DTO のデコード時点で URL を生成し、失敗なら `DecodingError` として扱う。`toDomain()` は URL 型を受け取るだけになる。

### 案 C: 最小限の対応

`guard let url = URL(string:) else { ... }` でフォールバック URL を返すか、該当フィールドを Optional にする。

## 補足: Date パースの silent fallback

同じ `toDomain()` 内で `.distantPast` にフォールバックしている日付パースも合わせて見直すとよい。

```swift
// GitHubRepoDetailDTO.swift:59-60
createdAt: formatter.date(from: createdAt) ?? .distantPast
updatedAt: formatter.date(from: updatedAt) ?? .distantPast
```

`.distantPast` は UI に「紀元前 68 年」のような日付を出す可能性がある。Optional にするか、`throws` で明示的にエラーにするのが安全。

## 影響範囲

- `Features/RepositoryDetail/Data/DTO/GitHubRepoDetailDTO.swift`
- `Features/IssueDetail/Data/DTO/GitHubIssueDetailDTO.swift`
- `Features/IssueList/Data/DTO/GitHubIssueDTO.swift`
- `Features/RepositorySearch/Data/DTO/GitHubSearchResponseDTO.swift`
- `Common/Networking/HttpClient.swift`（static URL は対応不要かもしれない）
- 関連テスト
