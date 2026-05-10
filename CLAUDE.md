# プロジェクト前提

- ユーザーとのやり取りでは、常に日本語を使用する。
- このリポジトリは iOS 17 以降を対象に、SwiftUI で実装する GitHub クライアントである。
- Swift 6 を使用し、strict concurrency を遵守する。
- 実装時は `github-client-swiftui/docs/requirements.md` の要求定義を前提にする。
- 状態管理には SwiftUI Observation の `@Observable` を使用し、`ObservableObject` / `@Published` は原則として採用しない。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` を設定済みのため、モジュール内の型・関数はデフォルトで `@MainActor` に隔離される。明示的な `@MainActor` 付与は不要。バックグラウンド実行が必要な箇所には `nonisolated` を付与する。
- アーキテクチャは View / Observable Model / Repository / API Client の分離を基本にする。
- ナビゲーションは `NavigationStack` のデータ駆動ナビゲーションを基本にし、`NavigationLink(value:)` と `.navigationDestination(for:)` を使用する。`NavigationView` は使用しない。
- 遷移状態は `Hashable` な typed route の配列で保持し、route には画面構築に必要な最小限の識別子だけを持たせる。
- SwiftUI Preview は `#Preview` を使用し、Repository / API Client を Mock に差し替えて loading / empty / error / loaded などの主要状態を確認できるようにする。
- avatar 画像ロードは再利用可能なコンポーネントと差し替え可能な画像ロード境界で扱い、`URLSession` / `URLCache` を使って HTTP キャッシュを尊重する。Preview / Test では画像ローダーも Mock に差し替える。
- 非同期処理は async/await と Task を使用する。Task cancellation は協調的に扱い、cancel はユーザー向けエラーとして表示しない。
- actor 境界や Task 境界をまたぐ型は `Sendable` を意識して設計し、`@unchecked Sendable` は原則として使用しない。
- テストは Swift Testing を主に使用する。
- GitHub API は初期実装では unauthenticated で利用し、将来的な認証機能追加に備えて API Client を差し替えやすくする。

# Xcode プロジェクト構成

- Xcode プロジェクトは `PBXFileSystemSynchronizedRootGroup` を使用している。ディスク上のフォルダ構造がそのまま Xcode のグループ構造に同期されるため、ファイルやフォルダの追加・削除・移動時に `pbxproj` を手動編集する必要はない。
- 新規ファイル作成時は適切なディレクトリに配置するだけでよく、`pbxproj` への参照追加は不要。

# Xcode ビルド・テスト・動作確認

- Xcode のビルド・テスト・シミュレータ操作は **必ず XcodeBuildMCP（`mcp__XcodeBuildMCP__*` ツール群）を使用する**。`xcodebuild` を Bash で直接実行してはならない。
- セッションで初めてビルド・テスト系のツールを呼ぶ前に、必ず `mcp__XcodeBuildMCP__session_show_defaults` を呼び、project / scheme / simulator が設定されているか確認する。未設定なら `mcp__XcodeBuildMCP__session_set_defaults` で設定する。
  - scheme: `github-client-swiftui`
  - simulator: `iPhone 17`（OS `26.4.1`）

## 標準フロー

コード変更後は以下の順で確認する：

1. **ビルド確認**: `mcp__XcodeBuildMCP__build_sim` を `extraArgs: ["build-for-testing"]` で呼び、プロダクトコードとテストコードの両方がコンパイル・リンクできることを確認する。
2. **テスト実行**: ビルドが通ったら**必ず** `mcp__XcodeBuildMCP__test_sim` でユニットテストを実走し、合否を確認する。変更が View レイヤや軽微な差分であってもスキップしない。
3. **動作確認**（必要に応じて）: `mcp__XcodeBuildMCP__build_run_sim` でアプリを起動し、画面・状態を観測したり操作したりする。観測には `screenshot` / `snapshot_ui` / `record_sim_video` を使い、UI 操作は `tap` / `swipe` / `type_text` などを使う。

## ログ観測

- アプリ起動時のレスポンスに含まれるログファイルパスを `Monitor` ツールで `tail -f` し、関心のあるパターンで `grep --line-buffered` するとリアルタイムにログをイベントとして受け取れる。追加読み込み・エラー発生など、操作とログの突き合わせが必要なときに使う。

## カバレッジ

- `mcp__XcodeBuildMCP__get_coverage_report` / `mcp__XcodeBuildMCP__get_file_coverage` を使う。
