# テスト設計ガイド

Swift / SwiftUI アプリケーションにおいて、**フレーキーにならず、テスタブルなプロダクションコードを書き、一流のテストコードを維持するための設計指針**をプロジェクトの実例に紐づけて整理する。

フレーキーテストの具体的な症状と回避策は [pitfalls/testing.md](../pitfalls/testing.md) に記録している。本書はその上位にある設計原則を扱う。

---

## 1. テスタブルなプロダクションコードの設計

テストの品質は、テストコードではなく **プロダクションコードの設計段階で決まる**。テストが書きにくいと感じたら、まずプロダクションコードの設計を疑う。

### 1.1 Protocol ベースの依存注入

外部リソース（API、DB、Keychain、UserDefaults）への依存は **Protocol で抽象化し、init で注入する**。テストでは Mock に差し替える。

```swift
// Protocol で境界を定義
nonisolated protocol GithubRepoRepositoryProtocol: Sendable {
    func searchRepositories(query: String, sort: String?, order: String?, page: Int) async throws -> RepositorySearchPageResult
    func fetchIssues(fullName: GitHubRepoFullName, page: Int) async throws -> [GitHubIssue]
}

// Model は Protocol に依存する
@Observable
final class IssueListModel {
    private let repository: GithubRepoRepositoryProtocol

    init(fullName: GitHubRepoFullName, repository: GithubRepoRepositoryProtocol) {
        self.repository = repository
    }
}
```

このプロジェクトでは View → Observable Model → Repository → API Client の 4 層すべてが Protocol 境界で分離されている。

### 1.2 Task の公開 — テストから非同期完了を await できる設計

`@Observable` Model が内部で `Task` を起動するとき、テストから **その Task の完了を確定的に待てる経路** を用意する。これがフレーキーテスト防止の最も重要な設計判断。

```swift
@Observable
final class IssueListModel {
    var inFlightTask: Task<Void, Never>? { currentTask }   // read-only で公開
    private var currentTask: Task<Void, Never>?

    func onAppear() {
        currentTask = Task { ... }
    }
}
```

テスト側:

```swift
private func waitForInflight(_ model: IssueListModel) async {
    await model.inFlightTask?.value
}

@Test func onAppear_success_transitionsToLoaded() async {
    let (model, _) = makeSUT()
    model.onAppear()
    await waitForInflight(model)    // Task の完了そのものを待つ
    guard case .loaded = model.phase else { ... }
}
```

`Task.sleep` で「十分な時間」を待つのではなく、**完了そのものを await する**。CI の負荷やテスト並列度に依存しない。

並行して走る Task が複数ある場合（例: `IssueDetailModel` の detail 取得と comments 取得）は、それぞれを個別に公開する:

```swift
var inFlightTask: Task<Void, Never>? { loadTask }
var commentsInFlightTask: Task<Void, Never>? { commentsTask }
```

### 1.3 テスト用パラメータの注入

タイミングに依存する内部パラメータ（debounce 時間、polling interval など）は init で注入可能にする。

```swift
init(
    repository: GithubRepoRepositoryProtocol,
    debounceDuration: Duration = .milliseconds(300),     // テストでは 0 に
    conditionStore: RepositorySearchConditionStore = ...,
    cache: RepositorySearchCache = ...
) { ... }
```

`DeviceFlowModel` の `intervalScale: Double` も同じ考え方。本番では `1.0`、テストでは `0.0` にして polling loop の `Task.sleep` を即座に通過させる。

### 1.4 状態を enum で表現する

画面の状態を複数の `Bool` フラグで管理すると、「あり得ない状態の組み合わせ」がテスト対象として爆発する。**enum で有限の状態だけを許す**設計にすると、テストケースが明確になり、テストの網羅性も確認しやすい。

```swift
enum IssueListPhase: Sendable, Equatable {
    case loading
    case loaded(LoadedIssues)
    case error(message: String)
}
```

`Equatable` 適合があれば `#expect(model.phase == .loading)` で直接比較できる。associated value がある case は `guard case let` でパターンマッチする。

---

## 2. Mock の設計

### 2.1 actor を使った並列安全な Mock

Swift Testing はデフォルトで Suite 内のテストを並列実行する。Mock が `class` で `var` を持つとデータ競合の危険がある。**actor で Mock を実装**すれば、言語機構でスレッド安全が保証される。

```swift
actor MockGithubRepoRepository: GithubRepoRepositoryProtocol {
    var searchResult: Result<RepositorySearchPageResult, Error>
    private(set) var searchCallCount = 0
    private(set) var lastPage: Int?
    // ...
}
```

テスト側では `await mock.searchCallCount` のようにアクセスする。actor hop のコストはテストでは問題にならない。

`nonisolated` + `OSAllocatedUnfairLock` パターン（`MockGitHubAuthService` で採用）は、**actor の関数 coloring を避けたい場合**（Protocol が `nonisolated` で定義されている場合）の選択肢。

### 2.2 Mock は本物と同じバリデーションを持つ

Mock がバリデーションを省略すると、テストでは通るが本番では到達しないコードパスを走り、**最悪のケースで無限ループ / ハング**を引き起こす。

```swift
// MockGitHubAuthService
func requestDeviceCode() async throws -> GitHubDeviceCode {
    _ = try clientID()   // 本物と同じバリデーション
    let result = stateLock.withLock { $0.deviceCodeResult }
    return try result.get()
}
```

`intervalScale: 0.0` でループを高速化するテスト環境では、ループが終了しないケースが即座にハングになるため、Mock のバリデーション漏れとの組み合わせが特に危険。

### 2.3 コール追跡

Mock に `callCount` / `lastArgument` プロパティを持たせて、**テスト側から「呼ばれたこと」「引数が正しいこと」を検証する**。

```swift
actor MockGithubRepoRepository: GithubRepoRepositoryProtocol {
    private(set) var fetchIssuesCallCount = 0
    private(set) var fetchIssuesLastPage: Int?

    func fetchIssues(fullName: GitHubRepoFullName, page: Int) async throws -> [GitHubIssue] {
        fetchIssuesCallCount += 1
        fetchIssuesLastPage = page
        return try issuesResult.get()
    }
}
```

テスト:

```swift
await #expect(mock.fetchIssuesCallCount == 1)
await #expect(mock.fetchIssuesLastPage == 2)
```

### 2.4 ハンドラによる柔軟な制御

固定値の `Result` だけでなく、クロージャベースのハンドラを用意すると、テストごとに動的な挙動を注入できる:

```swift
// 同期ハンドラ（引数に応じて結果を変えたい場合）
var issuesResultHandler: (@Sendable (GitHubRepoFullName, Int) -> Result<[GitHubIssue], Error>)?

// 非同期ハンドラ（ハンドラ内で suspend させたい場合）
var fetchAsyncHandler: (@Sendable (GitHubRepoFullName) async throws -> GitHubRepoDetail)?
```

非同期ハンドラは「リクエスト中の状態を観測したい」テストで特に有用（後述の Confirmation パターン）。

---

## 3. テストの隔離

### 3.1 UserDefaults の隔離

テストごとに UUID ベースの suiteName で専用の UserDefaults インスタンスを作る。テスト終了後に `removePersistentDomain` でクリーンアップする。

```swift
private func makeDefaults() -> UserDefaults {
    let suiteName = "IssueListModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
```

### 3.2 HTTP 通信の隔離

`StubURLProtocol` はテストごとに固有ホスト名 (`test-{UUID}.invalid`) を払い出し、レスポンスを global registry で管理する。詳細は [pitfalls/testing.md](../pitfalls/testing.md) を参照。

### 3.3 SUT ファクトリ (makeSUT)

テストごとに新しい Model + Mock のペアを生成するファクトリ関数を用意する。テスト間で状態を共有しない。

```swift
private func makeSUT(
    issuesResult: Result<[GitHubIssue], Error> = .success(GitHubIssue.samples)
) -> (model: IssueListModel, mock: MockGithubRepoRepository) {
    let mock = MockGithubRepoRepository(issuesResult: issuesResult)
    let model = IssueListModel(fullName: Self.fullName, repository: mock)
    return (model, mock)
}
```

デフォルト引数で「典型的な成功ケース」を表現し、個別テストでは「逸脱する部分だけ」を明示的に渡す。テストの読み手がノイズに埋もれずに意図を読み取れる。

---

## 4. 非同期テストのパターン

### 4.1 完了を await する（基本パターン）

テストしたい非同期処理が `Task` として公開されているなら、`await task.value` で完了を待つ。**これが最も安定した手法であり、常に第一選択肢**。

```swift
model.onAppear()
await model.inFlightTask?.value
#expect(model.phase == .loaded(...))
```

### 4.2 AsyncStream による明示的シグナル

「非同期ハンドラが実行を開始したこと」を待ちたいとき、`AsyncStream` を使ってハンドラ到達をシグナルする。`Task.yield()` の回数に依存しない確定的な同期。

```swift
let handlerReached = AsyncStream<Void>.makeStream()
await mock.setSearchAsyncHandler { @Sendable _, _, _, _ in
    handlerReached.continuation.yield()       // 到達を通知
    while !Task.isCancelled { await Task.yield() }
    throw CancellationError()
}
model.query = "swift"
for await _ in handlerReached.stream { break }  // 到達を待つ
model.onDisappear()                              // 確実にハンドラ実行中にキャンセル
```

### 4.3 Confirmation

Swift Testing が提供する `confirmation` は「コールバックが N 回呼ばれたことを待つ」ための仕組み。**ハンドラ到達の待機 + ハンドラ内からの resume 制御を組み合わせる**ときに使う。

```swift
await confirmation { handlerReached in
    await mock.setSearchAsyncHandler { @Sendable _, _, _, _ in
        handlerReached()                    // confirmation を satisfy
        for await _ in resume.stream { break }
        return refreshed
    }
    async let refreshFinished: Void = model.refresh()
    // ここに到達した時点でハンドラは suspend 中 → mid-state を観測できる
    guard case .loaded = model.phase else { ... }
    resume.continuation.yield()
    await refreshFinished
}
```

### 4.4 Task.yield() の使いどころ

`Task.yield()` は「MainActor に制御を返して pending の状態更新を反映させる」場合に使う。**ハンドラ到達やタイミング同期の手段としては使わない**。

適切な使用例:

```swift
model.start()
await Task.yield()     // model.start() が貼った Task の phase 更新を反映
#expect(model.phase == .polling(...))
```

不適切な使用例:

```swift
// NG: yield の回数で「ハンドラに到達したはず」を仮定している
model.query = "swift"
await Task.yield()
await Task.yield()
model.onDisappear()
```

### 4.5 Task.sleep が妥当なケース

`Task.sleep` ベースの待機が正当化されるのは **「何も起きないこと」を時間経過で確認する** テストに限られる。

```swift
// debounce 中にまだ API が発火していないことを確認する
let (model, mock) = makeSUT(debounceDuration: .milliseconds(100))
model.query = "swift"
try? await Task.sleep(for: .milliseconds(50))   // debounce 中
await #expect(mock.searchCallCount == 0)         // まだ呼ばれていない
```

**判断軸: 待ちたいのは「完了」か「時間経過」か。完了なら await、時間経過なら sleep。**

---

## 5. テストの命名と構造

### 5.1 テスト名は振る舞いを記述する

テスト名は「入力/操作 → 期待結果」の形式で、PRD の受入条件 (AC) に対応させる。実装の都合（メソッド名やクラス名）で命名しない。

```swift
// 良い: 振る舞いを記述
@Test func onAppear_success_transitionsToLoaded() async { ... }
@Test func loadNextPage_failure_keepsExistingItems() async { ... }
@Test func retry_afterError_refetches() async { ... }

// 悪い: 実装の都合で命名
@Test func testLoad() async { ... }
@Test func testFetchIssuesPage2() async { ... }
```

### 5.2 MARK セクションで意図を区切る

ユーザーストーリーや機能領域ごとに `// MARK:` で区切る。テストファイルを開いたときに全体の構造が一覧できる。

```swift
// MARK: - onAppear
// MARK: - pagination
// MARK: - retry
// MARK: - refresh
// MARK: - onDisappear (cancellation)
```

### 5.3 guard case let でフェーズを検証する

associated value を持つ enum のテストでは、`guard case let` でアンラップし、失敗時は `Issue.record` で具体的な状態を出力する。

```swift
guard case let .loaded(state) = model.phase else {
    Issue.record("Expected loaded, got \(model.phase)")
    return
}
#expect(state.issues == expected)
```

`if case let` + `else { Issue.record }` でも同じだが、`guard` のほうが early return の意図が明確で、アンラップした値をスコープ全体で使える。

---

## 6. テスト粒度の判断基準

### 6.1 テストファーストにすべきもの

- Observable Model のすべての公開メソッド（状態遷移・エラー処理・キャンセル）
- Repository / Mapper / 純粋ロジック
- DTO のデコード（フィールドの欠損、null 許容など）

### 6.2 テストファーストにしなくてよいもの

- SwiftUI View の構造（Preview で確認）
- `#Preview` 自体
- Apple フレームワークの素の挙動の確認のみのコード

### 6.3 過度にしない

同じコードパスを複数のテストが重複して通る場合は、テストが多すぎる可能性がある。テスト 1 つにつき **1 つの振る舞い**を検証するのが原則。パラメータのバリエーションは `@Test(arguments:)` でまとめる。

---

## 7. アンチパターン一覧

| やってはいけないこと | 理由 | 代替手段 |
|---|---|---|
| `Task.sleep` で非同期完了を待つ | CI 負荷やテスト並列度で破綻する | `await model.inFlightTask?.value` |
| `Task.yield()` の回数でハンドラ到達を仮定する | yield は実行順序を保証しない | `AsyncStream` / `Confirmation` で明示的にシグナルする |
| ハンドラ内で `#expect` する | テストランナーのコンテキスト外で失敗メッセージが不明瞭になる | ハンドラで値を capture し、テスト本体側で assert する |
| テスト間で Mock やストレージを共有する | 並列実行でデータ競合が起きる | テストごとに `makeSUT()` で新しいインスタンスを生成する |
| Mock がバリデーションを省略する | 本番と異なるコードパスを通り、ハング/無限ループの原因になる | 本物と同じ early return / throw を再現する |
| `@Suite(.serialized)` を安易に貼る | テスト実行時間が伸び、設計の問題が隠蔽される | §4 の手法で隔離・同期を設計する |
| `try?` で `Task.sleep` のエラーを握りつぶす | 意図しないキャンセルの検知ができない | sleep が `CancellationError` を投げるのは正常フローなので `try?` は許容されるが、await 完了待ちと混同しない |

---

## 8. このプロジェクトのテスト設計の全体像

```
テストファイル                         テスト対象                         キーとなる設計判断
─────────────────────────────────────────────────────────────────────────────────────────────
RepositorySearchModelTests            検索 Model (debounce / sort /      inFlightTask 公開
                                      qualifier / pagination)            debounceDuration 注入
                                                                         makeSUT ファクトリ
RepositorySearchModelCacheTests       キャッシュ命中 / miss / 無効化      AsyncStream でハンドラ同期
                                                                         Confirmation で mid-state 観測
RepositorySearchModelPersistenceTests 条件の永続化 / 復元                 UUID suiteName で UserDefaults 隔離
IssueListModelTests                   Issue 一覧 (pagination / retry)    inFlightTask 公開 + perPage 公開
IssueDetailModelTests                 detail + comments 並行取得         inFlightTask / commentsInFlightTask
RepositoryDetailModelTests            リポジトリ詳細取得                  inFlightTask 公開
BookmarkStoreTests                    ブックマーク CRUD / 永続化          in-memory init と persistent init
DeviceFlowModelTests                  OAuth Device Flow 状態遷移         intervalScale で sleep 圧縮
                                                                         OSAllocatedUnfairLock で poll 計数
SettingsModelTests                    プロフィール / ログアウト            SUT struct でコンテキストをまとめる
GitHubAuthStateTests                  認証状態管理                        同期テスト (Task 不要)
URLSessionHttpClientTests             HTTP クライアント                   StubURLProtocol + 固有ホスト隔離
AuthenticatedHttpClientTests          認証ヘッダ注入 / 401 処理          StubURLProtocol
GitHubAuthServiceTests                認証サービス                        StubURLProtocol + Mock Keychain
DeepLinkTests / AppCoordinatorTests   ディープリンク解析 / 遷移           純粋関数テスト (async 不要)
DTO Tests                             JSON デコード / マッピング          固定 JSON 文字列の round-trip
```

---

## 9. 一次ソース

- [Swift Testing — Testing asynchronous code](https://developer.apple.com/documentation/testing/testing-asynchronous-code) — `await` と `Confirmation` の公式推奨
- [Swift Testing — `Confirmation`](https://developer.apple.com/documentation/testing/confirmation) — コールバック発火を待つ API
- [Swift Testing — Running tests serially or in parallel](https://developer.apple.com/documentation/testing/parallelization) — Suite 内並列実行の仕組みと `.serialized`
- [Swift Testing — Organizing tests](https://developer.apple.com/documentation/testing/organizingtests) — `@Suite` / `@Test` の構造化
- [Swift Concurrency — `Task`](https://developer.apple.com/documentation/swift/task) — `Task.value` / `Task.isCancelled` / `Task.yield()`
- [SE-0304: Structured Concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md) — キャンセルの協調的性質
- [`OSAllocatedUnfairLock`](https://developer.apple.com/documentation/os/osallocatedunfairlock) — iOS 16+ の Sendable なロック
