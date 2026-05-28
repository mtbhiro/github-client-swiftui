# Environment デフォルト値の Mock 排除

## ステータス: 完了

## 概要

`GithubRepoRepository.swift` の `EnvironmentKey` デフォルト値が `MockGithubRepoRepository()` になっている。本番コードで Environment 注入が漏れた場合、クラッシュではなく Mock が動くため、バグを隠蔽するリスクがある。

## 現状のコード

```swift
// GithubRepoRepository.swift:89-93
private struct GithubRepoRepositoryEnvironmentKey: EnvironmentKey {
    // Preview / Test で .environment 未注入のまま動くよう Mock をデフォルトに置く。
    // 本番では `AuthStack` が必ず認証付きの実体を注入する。
    static let defaultValue: any GithubRepoRepositoryProtocol = MockGithubRepoRepository()
}
```

## 改善案

### 案 A: `fatalError` にする

```swift
static let defaultValue: any GithubRepoRepositoryProtocol = {
    fatalError("githubRepository environment key not injected")
}()
```

Preview で必ず `.environment(\.githubRepository, mock)` を書く必要があるが、注入漏れを即座に検知できる。

### 案 B: DEBUG ビルドのみ Mock

```swift
static let defaultValue: any GithubRepoRepositoryProtocol = {
    #if DEBUG
    return MockGithubRepoRepository()
    #else
    fatalError("githubRepository environment key not injected")
    #endif
}()
```

Preview の利便性を保ちつつ、リリースビルドでは注入漏れを検知する。

## 影響範囲

- `Common/Repository/GithubRepoRepository.swift`
- 全ての `#Preview` で `.environment(\.githubRepository, ...)` の注入が必要になる可能性
