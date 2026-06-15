# プロジェクト前提

- ユーザーとのやり取りでは、常に日本語を使用する。
- このリポジトリは iOS 17 以降を対象に、SwiftUI で実装する GitHub クライアントである。
- Swift 6 を使用し、strict concurrency を遵守する。
- 実装時は `github-client-swiftui/docs/requirements.md` の要求定義を前提にする。
- 状態管理には SwiftUI Observation の `@Observable` を使用し、`ObservableObject` / `@Published` は原則として採用しない。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` を設定済みのため、モジュール内の型・関数はデフォルトで `@MainActor` に隔離される。明示的な `@MainActor` 付与は不要。バックグラウンド実行が必要な箇所には `nonisolated` を付与する。
- 独自に `actor` を定義するのは「UI と独立した共有可変状態が複数 Task から触られる」場合に限る。判断軸とトレードオフは `github-client-swiftui/docs/guide/actor-guide.md` を参照。
- アーキテクチャは View / Observable Model / Repository / API Client の分離を基本にする。
- ナビゲーションは `NavigationStack` のデータ駆動ナビゲーションを基本にし、`NavigationLink(value:)` と `.navigationDestination(for:)` を使用する。`NavigationView` は使用しない。
- 遷移状態は `Hashable` な typed route の配列で保持し、route には画面構築に必要な最小限の識別子だけを持たせる。
- SwiftUI Preview は `#Preview` を使用し、Repository / API Client を Mock に差し替えて loading / empty / error / loaded などの主要状態を確認できるようにする。
- avatar 画像ロードは再利用可能なコンポーネントと差し替え可能な画像ロード境界で扱い、`URLSession` / `URLCache` を使って HTTP キャッシュを尊重する。Preview / Test では画像ローダーも Mock に差し替える。
- 非同期処理は async/await と Task を使用する。Task cancellation は協調的に扱い、cancel はユーザー向けエラーとして表示しない。
- actor 境界や Task 境界をまたぐ型は `Sendable` を意識して設計する（`@unchecked Sendable` は SwiftLint で禁止）。
- テストは Swift Testing を主に使用する。
- GitHub API は初期実装では unauthenticated で利用し、将来的な認証機能追加に備えて API Client を差し替えやすくする。

# Swift / SwiftUI コードを書くときのルール

Swift / SwiftUI コード（プロダクトコード・テストコード）の編集に着手する前に **必ず `.claude/rules/swift-coding.md` を読む**。本書の前提と整合する形で、状態モデル・非同期/キャンセル戦略・テストファースト運用・困ったときの参照先などを集約している。

## Apple 公式 Agent Skills

SwiftUI のベストプラクティスは Apple 公式 Agent Skills（Xcode 27 同梱）を一次ソースとする。以下の 3 Skills を `.claude/skills/` に導入済み:

- **`/swiftui-specialist`** — SwiftUI の View 構造・データフロー・Environment・modifier・ForEach・localization・animation・soft-deprecated API
- **`/swiftui-whats-new-27`** — SDK 27 の新 API（`@State` マクロ化・`AsyncImage` キャッシュ・reorderable・swipe actions・toolbar overflow 等）
- **`/test-modernizer`** — XCTest → Swift Testing 移行ガイダンス

SwiftUI API の使い方に迷ったらまず公式 Skills を参照する。`.claude/rules/swift-coding.md` はプロジェクト固有のルール（並行性・アーキテクチャ層・ナビゲーション・テスト運用・flaky 防止等）に集中している。

# Xcode プロジェクト構成

- Xcode プロジェクトは `PBXFileSystemSynchronizedRootGroup` を使用している。ディスク上のフォルダ構造がそのまま Xcode のグループ構造に同期されるため、ファイルやフォルダの追加・削除・移動時に `pbxproj` を手動編集する必要はない。
- 新規ファイル作成時は適切なディレクトリに配置するだけでよく、`pbxproj` への参照追加は不要。

# Xcode ビルド・テスト・動作確認

- Xcode のビルド・テスト・シミュレータ操作は **必ず XcodeBuildMCP（`mcp__XcodeBuildMCP__*` ツール群）を使用する**。`xcodebuild` を Bash で直接実行してはならない。
- セッションで初めてビルド・テスト系のツールを呼ぶ前に、必ず `mcp__XcodeBuildMCP__session_show_defaults` を呼び、project / scheme / simulator が設定されているか確認する。未設定なら `mcp__XcodeBuildMCP__session_set_defaults` で設定する。
  - scheme: `github-client-swiftui`
  - simulator: `iPhone 17`（OS `26.5`、ID `BF5AFD63-1EEE-4B84-8618-392F1781B17C`）

## 標準フロー

コード変更後は以下の順で確認する：

1. **ビルド確認**: `mcp__XcodeBuildMCP__build_sim` を `extraArgs: ["build-for-testing"]` で呼び、プロダクトコードとテストコードの両方がコンパイル・リンクできることを確認する。型エラー・strict concurrency 違反はここで検知される。
2. **テスト実行**: ビルドが通ったら `mcp__XcodeBuildMCP__test_sim` でユニットテストを実走し、合否を確認する。呼び出し時は **必ず `extraArgs: ["-skip-testing:github-client-swiftuiUITests"]` を渡して UI テストターゲットをスキップする**（UI テストは現状空のテンプレートで、実行すると configuration ごとにシミュレータが多重起動するため）。
3. **動作確認**（必要に応じて）: `mcp__XcodeBuildMCP__build_run_sim` でアプリを起動し、画面・状態を観測したり操作したりする。観測には `screenshot` / `snapshot_ui` / `record_sim_video` を使い、UI 操作は `tap` / `swipe` / `type_text` などを使う。

### `test_sim` の呼び出し頻度

`test_sim` は呼び出すたびにシミュレータをブートする。タスクごとに `-only-testing:...` で 1 ファイルずつ繰り返し叩くと、シミュレータが何個も起動して環境を食い潰す。以下のルールで頻度を抑える：

- **タスクごとに `test_sim` を呼ばない**。複数タスクで追加したテストは **1 回の `test_sim` 呼び出しに `-only-testing:` を複数並べてまとめて流す**。`-only-testing` は繰り返し指定できる。
- **型・コンパイルの確認だけなら `build_sim` で十分**（テストランナーが起動せずシミュレータがブートされない）。Red 確認・並列レース調査・テスト同士の干渉切り分けなど、実走しないと分からないケースのみ `test_sim` を呼ぶ。
- **フェーズの最終確認では `-only-testing` を外して全テスト 1 回**で流す。
- 詳細は `github-client-swiftui/docs/pitfalls/xcodebuild-mcp.md` の「`test_sim` をタスク単位で何度も呼んでシミュレータがゾンビ化する」を参照。

## ログ観測

- アプリ起動時のレスポンスに含まれるログファイルパスを `Monitor` ツールで `tail -f` し、関心のあるパターンで `grep --line-buffered` するとリアルタイムにログをイベントとして受け取れる。追加読み込み・エラー発生など、操作とログの突き合わせが必要なときに使う。

## カバレッジ

- `mcp__XcodeBuildMCP__get_coverage_report` / `mcp__XcodeBuildMCP__get_file_coverage` を使う。

## SourceKit のエラー表示について

- Xcode / SourceKit-LSP は Claude Code の外側からの編集に index が追いつかず、実際には問題のないエラーを一時的に表示することがある（既知の挙動）。
- 真偽の判定は常に XcodeBuildMCP のビルド・テスト結果で行う。ビルド・テストが通っているなら SourceKit の表示を根拠に再調査・修正をしない。

# SwiftLint

- SwiftLint を SPM Plugin（`SimplyDanny/SwiftLintPlugins`）として導入済み。ビルド時に自動で lint が走る。
- 設定は `.swiftlint.yml`（リポジトリルート）。デフォルトルールをベースに、`force_cast` / `force_unwrapping` を error、`@unchecked Sendable` をカスタムルールで禁止している。
- SwiftLint の警告・エラーはビルド結果に表示される。ビルドを通す＝ lint も通っている。
- XcodeBuildMCP でビルドする際は `-skipPackagePluginValidation` を `extraArgs` に追加する。

# 既知の落とし穴

挙動が想定と違う・自動化が変な失敗をする・などで困ったときは `github-client-swiftui/docs/pitfalls/` を参照する。テーマ別に Markdown が置かれている（索引は `docs/pitfalls/README.md`）。
