# Swift / SwiftUI 実装ルール

本リポジトリで Swift / SwiftUI コード（プロダクトコード・テストコード）を書く・編集するときの共通ルール。
スキル（`/developer` 等）と hook の両方から参照される。

> 前提となるプロジェクト規約（対応 OS・採用フレームワーク・状態管理方針など）は **ルート `CLAUDE.md`** と **`github-client-swiftui/docs/requirements.md`** を参照する。本書は「コードを書く・編集する瞬間」に効くルールに絞る。

## 1. 並行性 (Concurrency)

### 1.1 基本方針

- **Swift 6 strict concurrency を遵守する**。コンパイル警告を残さない。
- **非同期は async/await と Task** で書く。コールバック・Combine・`@Published` は採用しない。
- **`@unchecked Sendable` は使わない**（SwiftLint `unchecked_sendable` ルールで検出される）。

### 1.2 隔離 (isolation) の選び方

`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 設定済み。**型・関数はデフォルトで `@MainActor`**。
新しく型を作るときは、まずこの表で何を選ぶか決める。

| 何を作るか | 何を選ぶか |
|---|---|
| UI 状態を持つ Observable Model | デフォルトのまま (`@MainActor class` + `@Observable`) |
| ネットワーク / DB / デコード / 純粋ロジック / DTO / ドメインモデル | `nonisolated` を明示（多くは `struct`） |
| UI に関係しない共有可変状態（キャッシュ・テスト Mock など） | `actor` |

選び方の原則:

- `@MainActor` の明示は **不要**（デフォルト）。`nonisolated` のほうを明示する。
- `actor` の採用は **「複数 Task から触る可変状態」が本当にあるとき**だけ。1 Task からしか触らないなら struct か nonisolated class で十分。`actor` のメリット・デメリット・採用判断は `docs/guide/actor-guide.md` を読む。
- `OSAllocatedUnfairLock` / `Mutex` などのロックプリミティブは、**actor で表現できない理由が明確なときだけ**使う（function coloring を避けたい・同期コンテキストから触りたい等）。
- `@MainActor` / `nonisolated` の細かい取り回しは `docs/guide/actor-isolation-guide.md`。

### 1.3 Sendable

- actor 境界・Task 境界をまたぐ型は `Sendable` を意識して設計する。
- 適合に迷ったら `docs/guide/sendable-guide.md`。

### 1.4 Task キャンセル

- **キャンセルは協調的**。`await` 後は必要に応じて `Task.checkCancellation()` / `Task.isCancelled` を確認する。
- **`CancellationError` はユーザー向けエラーとして表示しない**（黙って捨てる）。
- 詳細は `docs/guide/task-cancellation-guide.md`。

## 2. 状態管理・アーキテクチャ

- 状態管理は **SwiftUI Observation の `@Observable`** を使う。`ObservableObject` / `@Published` は採用しない。
- 層は **View / Observable Model / Repository / API Client** の 4 層を基本にする。それぞれの責務を混ぜない。
- 状態は **`enum` で表現可能なら enum** を優先する（`idle / loading / loaded(...) / empty / error(...)` 等）。複数の `Bool` フラグで状態を表現しない。
- **抽象化は前倒しにしない**。同じパターンが 2 回出た時点では抽象化しない。3 回目で初めて検討する。
- **`didSet` で副作用（API 呼び出し・Task 生成など）を発火しない**。`didSet` 副作用 + 抑制フラグ（`suppressXxx`）のパターンは状態遷移が暗黙的になり壊れやすい。プロパティは値の保持に徹し、副作用は明示的なメソッド呼び出しか View の `.onChange(of:)` で発火する。
- **DI の `EnvironmentKey.defaultValue` に Mock を入れない**。注入漏れが本番で黙って Mock 動作になりバグを隠蔽する。`#if DEBUG` で Mock / Release で `fatalError` にするか、Protocol に対して明示的に注入を必須にする。

## 3. ナビゲーション

- ナビゲーションは **`NavigationStack` のデータ駆動** を基本にする。`NavigationView` は使わない。
- `NavigationLink(value:)` と `.navigationDestination(for:)` を使う。
- 遷移状態は **`Hashable` な typed route の配列** で保持する。route には画面構築に必要な最小限の識別子だけを持たせる（API 取得済みのモデル全体を載せない）。
- 既存の `Common/Navigation/AppRoute.swift` / `AppCoordinator.swift` のパターンに合わせる。
- 詳細は `github-client-swiftui/docs/guide/navigation-guide.md` を参照する。

## 4. SwiftUI Preview

- **`#Preview` を使う**。`PreviewProvider` プロトコル形式は採用しない。
- Repository / API Client / 画像ローダーは Preview で **Mock に差し替える**。loading / empty / error / loaded など主要状態の Preview を用意する。
- Preview に時間のかかる本物の API 通信を流さない。

## 5. 画像・avatar

- avatar 画像のロードは **再利用可能なコンポーネント** と **差し替え可能な画像ロード境界** で扱う。`URLSession` / `URLCache` を使って HTTP キャッシュを尊重する。
- Preview / Test では画像ローダーも Mock に差し替える。
- avatar 画像のロード失敗は **画面全体の error 状態にしない**（要求定義 §3.5）。

## 6. テスト（Swift Testing）

- テストは **Swift Testing** を主に使う（`@Test` / `#expect` / `#require`）。`XCTest` は新規には書かない。
- **TDD を基本にする**。Observable Model / Repository / Mapper / 純粋ロジックは **テストファースト**（Red → Green → Refactor）。
- テスト名は **PRD の AC を写したもの** にする。「<入力 / 操作> したとき <観測可能な結果> になる」形式。実装の都合（メソッド名）で名付けない。
- **TDD を緩めてよいケース**: View の構造、`#Preview` 自体、Apple フレームワーク素の挙動の確認のみのコード。緩める判断をしたら、その理由を 1 行で残す。
- Mock 化は既存の `Common/Repository/MockGithubRepoRepository.swift` 等のパターンを踏襲する。新規 Mock を導入する前に既存を読む。
- **stub state の競合に注意**（`docs/pitfalls/testing.md`）。`StubURLProtocol` はテストごとに固有ホスト (`test-{UUID}.invalid`) を払い出して responder を分離している。新規に static / global state を持つ stub を作るときは、同様にテストインスタンス単位で key を分けて並列実行下のレースを設計時点で潰す。
- **`Task.sleep` で完了を待つテストを書かない**。Model 内 Task の完了を待ちたいときは、Model に inflight Task を読める read-only プロパティを生やし `await task?.value` で待つ。`await` できない callback 経由なら `Confirmation` を使う。`Task.sleep` ベースの待機は「何も起きないこと」「debounce 等の本質的に時間経過を見たい」場合にだけ使う。詳細は `docs/pitfalls/testing.md`。
- **`@Suite(.serialized)` は最終手段**。先に「(1) 完了を await できる経路を作る、(2) Confirmation、(3) テスト固有の独立リソース (UserDefaults suiteName など)、(4) Mock の actor → ロック化」を検討する。それでも解決できない（`StubURLProtocol` の static state のように根本書き換えが大コスト等）ケースに限って暫定的に貼る。詳細は `docs/pitfalls/testing.md`。
- 新規追加した Observable Model / Repository / Mapper のテストは、PRD §3 の AC と PRD §9 の検証要件に **1 対 1 で対応** させる。
- **flaky テストは絶対に書かない**。テストは並列実行環境（Xcode の並列テスト）で 100% 安定して通ることが必須。以下を守る：
  - `intervalScale: 0.0` 等でループを高速化する Mock は、**並列テストで MainActor を奪い合ったときにもハングしない**ことを確認する。
  - Mock は本物の実装と同じバリデーション（例: `clientID()` チェック）を行い、本物では到達しないコードパスをテストが通らないようにする。Mock がバリデーションを省略すると、テストでは成功扱いだが実際には無限ループに入るなどの事故が起きる。
  - `await model.inFlightTask?.value` で Task 完了を待つパターンでは、Task が確実にセットされてから await すること。Task のライフサイクル（開始・完了・キャンセル）を明確に追えない設計のテストは書き直す。
  - テストがハングする（タイムアウトなしで永久に返らない）のは **最悪のケース**。CI もローカルも止まる。ハングの可能性があるテストを書いたら、そのテストだけを 10 回連続で実行して安定性を確認する。

## 7. 防御的データ変換・ネットワーク

### 7.1 DTO → ドメインモデル変換

- **外部入力（API レスポンス）を `!` で強制アンラップしない**。`URL(string:)!`・`date(from:)!` 等は API が不正値を返した時点でクラッシュする。`guard let ... else { throw }` で `DTOMappingError` を投げる。
- **silent fallback（`?? .distantPast` 等）を使わない**。不正値を黙ってデフォルトに置き換えると、UI に意味不明な表示（紀元前の日付など）が出て原因追跡が困難になる。変換に失敗したら `throws` でエラーを伝播し、Repository 層で適切にハンドリングする。
- `toDomain()` は原則 `throws` にし、呼び出し元（Repository）の既存の `throws` チェーンに乗せる。

### 7.2 ネットワーククライアント

- **`URLSession.shared` を本番コードでそのまま使わない**。OS デフォルトのタイムアウト（60 秒）はモバイルアプリには長すぎる。専用の `URLSessionConfiguration` でタイムアウト（`timeoutIntervalForRequest` / `timeoutIntervalForResource`）を明示的に設定する。
- テスト用の `StubURLProtocol` セッションには影響しないため、本番用ファクトリメソッド（`makeDefaultSession()` 等）で設定を集約する。

## 8. コーディングスタイル（プロジェクト方針）

- **コメントは最小限**。意図が自明なコメントは書かない。WHY が非自明なときだけ短く残す（CLAUDE.md の方針）。
- **既存規約の再掲を避ける**。CLAUDE.md / requirements.md にあるルールはコード内コメントで繰り返さない。
- **emoji を勝手に入れない**。ユーザー要求が無ければ使わない。
- 削除コードに `// removed` 等のマーカーを残さない。削除はそのまま削除する（git で履歴は追える）。
- フォーマットは既存ファイルに揃える。新規ファイルでは Xcode のデフォルト（4-space indent）に従う。

## 9. 困ったときの参照先

挙動・設計に迷ったら **推測で書かず**、以下を順に当たる:

1. **プロジェクト規約**: ルート `CLAUDE.md`、`github-client-swiftui/docs/requirements.md`、機能別 PRD（`docs/requirements/<slug>.md`）。
2. **ガイド**: `github-client-swiftui/docs/guide/`
   - `actor-isolation-guide.md` — `@MainActor` / `nonisolated` の取り回し
   - `actor-guide.md` — 独自 `actor` 型をいつ・なぜ使うか／メリット・デメリット・reentrancy
   - `sendable-guide.md` — `Sendable` の付け方・避け方
   - `task-cancellation-guide.md` — Task キャンセルの伝搬・協調キャンセル
   - `navigation-guide.md` — `NavigationStack` data-driven の組み立て
   - `testing-design-guide.md` — テスタブルな設計・フレーキー防止・Mock 設計・非同期テストパターン
3. **落とし穴**: `github-client-swiftui/docs/pitfalls/README.md` を索引にして該当ファイル。
   - `testing.md` — Swift Testing 並列実行と stub race
   - `xcodebuild-mcp.md` — XcodeBuildMCP / AXe の既知の癖
4. **Apple 公式ドキュメント**: `mcp__cupertino__search` / `mcp__cupertino__read_document` / `mcp__cupertino__search_concurrency` / `mcp__cupertino__search_symbols`。Swift Concurrency・SwiftUI Observation・NavigationStack・URLSession などフレームワーク挙動の細部はここで一次ソースを取る。

## 10. やってはいけないこと（チェックリスト）

- [ ] `@unchecked Sendable` を使った（SwiftLint で自動検出）
- [ ] `ObservableObject` / `@Published` を新規に導入した
- [ ] `NavigationView` を使った / `NavigationLink(value:)` 以外の遷移を新規に作った
- [ ] テストファーストにできるロジックを View 経由でしかカバーしていない
- [ ] Task キャンセルをユーザー向けエラーとして表示した
- [ ] PRD の対象外（§2.2 / §10）に手を出した
- [ ] テストで `Task.sleep` ベースの polling で完了を待った（§6 の代替策を検討せず）
- [ ] §6 の代替策を検討せずに `@Suite(.serialized)` を貼った
- [ ] タスク（=テストファイル）ごとに `mcp__XcodeBuildMCP__test_sim` を `-only-testing:` 単発で呼んだ — シミュレータが多重起動するので、複数タスク分のテストを 1 回の `test_sim` にまとめる（`-only-testing` は繰り返し指定可、詳細は `docs/pitfalls/xcodebuild-mcp.md`）
- [ ] flaky テストを書いた / 既存テストを flaky にした — 並列実行で 100% 安定して通らないテストはマージ禁止。Mock のバリデーション省略（本物と異なる分岐）や `intervalScale: 0.0` での無限ループ、タイミング依存の assertion は全てハングや flaky の原因になる
- [ ] 外部入力（API レスポンス）に対して `!` で強制アンラップした — `URL(string:)!` / `date(from:)!` 等。`guard let` + `throw` を使う（§7.1）
- [ ] DTO 変換で silent fallback（`?? .distantPast` / `?? ""` 等）を使った — 不正値はエラーとして伝播する（§7.1）
- [ ] `didSet` で副作用（API 呼び出し・Task 生成）を発火した — 明示的メソッドか `.onChange(of:)` を使う（§2）
- [ ] `EnvironmentKey.defaultValue` に本番で動く Mock を入れた — `#if DEBUG` ガードを付ける（§2）
- [ ] `URLSession.shared` を本番コードでタイムアウト設定なしに使った — 専用 Configuration を作る（§7.2）

上記のいずれかに該当しそうになったら、コードを書く手を止めて理由を整理する。

> ビルド・テスト実行（XcodeBuildMCP のフロー、`-skip-testing:github-client-swiftuiUITests` 必須）と Xcode プロジェクト構成（`PBXFileSystemSynchronizedRootGroup` / `pbxproj` を手編集しない）は、コードを書く瞬間ではなく **ビルド/テスト実行の瞬間** に効くルールなので、ルート `CLAUDE.md` を参照する。`/developer` スキルのフェーズ 5 もそこに準拠する。
