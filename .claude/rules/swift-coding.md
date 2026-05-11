# Swift / SwiftUI 実装ルール

本リポジトリで Swift / SwiftUI コード（プロダクトコード・テストコード）を書く・編集するときの共通ルール。
スキル（`/developer` 等）と hook の両方から参照される。

> 前提となるプロジェクト規約（対応 OS・採用フレームワーク・状態管理方針など）は **ルート `CLAUDE.md`** と **`github-client-swiftui/docs/requirements.md`** を参照する。本書は「コードを書く・編集する瞬間」に効くルールに絞る。

## 1. 言語・並行性

- **Swift 6 strict concurrency を遵守する**。コンパイル警告も無視しない。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` が設定済み。**モジュール内の型・関数はデフォルトで `@MainActor`**。明示的な `@MainActor` 付与は不要。バックグラウンド実行が必要な箇所には `nonisolated` を付与する。
- **`@unchecked Sendable` は使わない**。どうしても必要に見えたら、Mutex / actor / 値型化など別案を先に検討する。判断に迷ったら `github-client-swiftui/docs/guide/sendable-guide.md` を読み返す。
- actor 境界や Task 境界をまたぐ型は `Sendable` を意識して設計する。
- **非同期処理は async/await と Task** を使う。コールバック・Combine の `@Published` は採用しない。
- **Task キャンセルは協調的に扱う**。`CancellationError` をユーザー向けエラーとして表示しない（黙って捨てる）。`await` 後は必要に応じて `Task.checkCancellation()` / `Task.isCancelled` を確認する。

## 2. 状態管理・アーキテクチャ

- 状態管理は **SwiftUI Observation の `@Observable`** を使う。`ObservableObject` / `@Published` は採用しない。
- 層は **View / Observable Model / Repository / API Client** の 4 層を基本にする。それぞれの責務を混ぜない。
- 状態は **`enum` で表現可能なら enum** を優先する（`idle / loading / loaded(...) / empty / error(...)` 等）。複数の `Bool` フラグで状態を表現しない。
- **抽象化は前倒しにしない**。同じパターンが 2 回出た時点では抽象化しない。3 回目で初めて検討する。

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
- **stub state の競合に注意**（`docs/pitfalls/testing.md`）。`URLSessionHttpClientTests` 系では `@Suite(.serialized)` で逐次実行している。同様の static stub を新規に作るときは並列実行下のレースを設計時点で潰す。
- 新規追加した Observable Model / Repository / Mapper のテストは、PRD §3 の AC と PRD §9 の検証要件に **1 対 1 で対応** させる。

## 7. コーディングスタイル（プロジェクト方針）

- **コメントは最小限**。意図が自明なコメントは書かない。WHY が非自明なときだけ短く残す（CLAUDE.md の方針）。
- **既存規約の再掲を避ける**。CLAUDE.md / requirements.md にあるルールはコード内コメントで繰り返さない。
- **emoji を勝手に入れない**。ユーザー要求が無ければ使わない。
- 削除コードに `// removed` 等のマーカーを残さない。削除はそのまま削除する（git で履歴は追える）。
- フォーマットは既存ファイルに揃える。新規ファイルでは Xcode のデフォルト（4-space indent）に従う。

## 8. 困ったときの参照先

挙動・設計に迷ったら **推測で書かず**、以下を順に当たる:

1. **プロジェクト規約**: ルート `CLAUDE.md`、`github-client-swiftui/docs/requirements.md`、機能別 PRD（`docs/requirements/<slug>.md`）。
2. **ガイド**: `github-client-swiftui/docs/guide/`
   - `actor-isolation-guide.md` — `@MainActor` / `nonisolated` の取り回し
   - `sendable-guide.md` — `Sendable` の付け方・避け方
   - `task-cancellation-guide.md` — Task キャンセルの伝搬・協調キャンセル
   - `navigation-guide.md` — `NavigationStack` data-driven の組み立て
3. **落とし穴**: `github-client-swiftui/docs/pitfalls/README.md` を索引にして該当ファイル。
   - `testing.md` — Swift Testing 並列実行と stub race
   - `xcodebuild-mcp.md` — XcodeBuildMCP / AXe の既知の癖
4. **Apple 公式ドキュメント**: `mcp__cupertino__search` / `mcp__cupertino__read_document` / `mcp__cupertino__search_concurrency` / `mcp__cupertino__search_symbols`。Swift Concurrency・SwiftUI Observation・NavigationStack・URLSession などフレームワーク挙動の細部はここで一次ソースを取る。

## 9. やってはいけないこと（チェックリスト）

- [ ] `@unchecked Sendable` を使った
- [ ] `ObservableObject` / `@Published` を新規に導入した
- [ ] `NavigationView` を使った / `NavigationLink(value:)` 以外の遷移を新規に作った
- [ ] テストファーストにできるロジックを View 経由でしかカバーしていない
- [ ] Task キャンセルをユーザー向けエラーとして表示した
- [ ] PRD の対象外（§2.2 / §10）に手を出した

上記のいずれかに該当しそうになったら、コードを書く手を止めて理由を整理する。

> ビルド・テスト実行（XcodeBuildMCP のフロー、`-skip-testing:github-client-swiftuiUITests` 必須）と Xcode プロジェクト構成（`PBXFileSystemSynchronizedRootGroup` / `pbxproj` を手編集しない）は、コードを書く瞬間ではなく **ビルド/テスト実行の瞬間** に効くルールなので、ルート `CLAUDE.md` を参照する。`/developer` スキルのフェーズ 5 もそこに準拠する。
