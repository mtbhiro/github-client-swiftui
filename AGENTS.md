# プロジェクト前提

- ユーザーとのやり取りでは、常に日本語を使用する。
- このリポジトリは iOS 17 以降を対象に、SwiftUI で実装する GitHub クライアントである。
- Swift 6 を使用し、strict concurrency を遵守する。
- 実装時は `docs/requirements.md` の要求定義を前提にする。
- 状態管理には SwiftUI Observation の `@Observable` を使用し、`ObservableObject` / `@Published` は原則として採用しない。
- UI 状態を持つ Observable Model は原則として `@MainActor` に隔離する。
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

# xcodebuild による品質保証

- コード変更後はビルドとテストビルドで品質を確認する。
- **シミュレータを起動してはならない。** `xcodebuild test` はシミュレータを起動しアプリを実行するため使用禁止。
- ビルド確認には `build-for-testing` を使用する。これはコンパイルとテストターゲットのリンクのみを行い、シミュレータを起動しない。
- ユニットテスト実行が必要な場合は `test-without-building` を使い、事前に起動済みのシミュレータがある場合のみ実行する。通常は `build-for-testing` の成功で十分とする。
- destination は `'platform=iOS Simulator,name=iPhone 17,OS=26.4.1'` を使用する。
- コマンド例:
  ```sh
  # ビルド確認（テストターゲット含む）
  xcodebuild -scheme github-client-swiftui -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' build-for-testing
  ```
