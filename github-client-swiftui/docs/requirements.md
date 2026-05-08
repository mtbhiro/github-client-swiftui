# 要求定義書

## 1. 概要

このプロジェクトは、SwiftUI で実装する iOS 向け GitHub クライアントである。
ユーザーはリポジトリを検索し、リポジトリ詳細、Issue / Pull Request 一覧、Issue / Pull Request 詳細を確認できる。

本ドキュメントは初期の要求定義であり、今後詳細化する前提とする。

## 2. 開発前提

### 2.1 対象・採用技術

- 対象 OS は iOS 17 以降とする。
- Swift 6 を使用する。
- strict concurrency を遵守する。
- UI は SwiftUI で実装する。
- 状態管理には SwiftUI Observation の `@Observable` を使用する。
- `ObservableObject` / `@Published` は原則として採用しない。必要な場合は比較対象または移行元の概念として扱う。
- 非同期処理は Swift Concurrency の async/await と Task を使用する。
- テストは Swift Testing を主に使用する。

### 2.2 GitHub API

- 初期実装では unauthenticated な GitHub REST API を利用する。
- API Client は将来的な認証機能追加を前提にし、token 付与や認証ヘッダー差し替えができる構造にする。
- rate limit を考慮し、HTTP エラーとして扱えるようにする。
- ページングは GitHub API のページ指定またはレスポンスヘッダーを扱える形で設計する。
- Issue と Pull Request の判定は API レスポンス上の Pull Request 情報の有無で行う。

### 2.3 初期スコープ外

- 認証機能は初期実装では扱わない。ただし将来追加できる設計にする。
- iPad 向けの複数カラム UI は初期実装では必須にしない。
- deep link、タブ構成、独自 Coordinator / Router は初期実装では必須にしない。
- 外部画像ライブラリは初期実装では採用しない。必要になった場合は要件を整理してから検討する。
- 永続保存を前提にした独自画像 DB は初期実装では採用しない。

## 3. 機能要件

### 3.1 リポジトリ検索

- キーワードでリポジトリ検索ができる。
- 入力に debounce が効いている。
- 新しい検索時に前のリクエストがキャンセルされる。
- 検索中は loading 表示を出す。
- 結果が空なら empty 表示を出す。
- エラー時は error 表示を出し、retry できる。
- 検索結果をタップするとリポジトリ詳細画面へ遷移できる。

### 3.2 リポジトリ詳細

- リポジトリ情報を表示できる。
- 表示項目は `name` / `owner` / `owner avatar` / `description` / `stars` / `forks` / `language` とする。
- 必要に応じて詳細 API を呼べる。
- loading / error / retry がある。
- Issue / Pull Request 一覧画面へ遷移できる。

### 3.3 Issue / Pull Request 一覧

- Issue / Pull Request 一覧を表示できる。
- Issue と Pull Request を見分けられる。
- 初回ロードで loading 表示を出す。
- 空なら empty 表示を出す。
- エラー時に retry できる。

#### ページング

- スクロールで次ページを取得できる。
- 次ページ取得中はフッターに loading 表示を出す。
- 多重リクエストが発生しない。
- 最終ページで止まる。
- 次ページエラー時は一覧を保持したまま retry できる。

#### Pull to Refresh

- Pull to Refresh ができる。
- Refresh 時に一覧がリセットされる。
- Refresh 中は専用の loading 状態になる。
- Refresh 後にページング状態が正しく復元される。

### 3.4 Issue / Pull Request 詳細

- タイトル・本文を表示できる。
- author / author avatar / labels / comments 数を表示できる。
- コメント一覧を取得できる。
- コメント author の avatar を表示できる。
- コメントの loading / error / retry が独立している。
- 画面遷移時に不要な処理がキャンセルされる。

### 3.5 Avatar 表示

- リポジトリ owner、Issue / Pull Request author、コメント author の avatar 画像を表示対象にする。
- 画像ロード中は placeholder を表示する。
- 画像ロード失敗時は fallback avatar を表示する。
- avatar 画像の失敗は画面全体の error 状態にしない。

## 4. 共通 UI 状態要件

- loading / empty / error / loaded を区別して扱う。
- 初回ロードとページングロードを区別する。
- refresh と通常ロードを区別する。
- error と cancel を区別して扱う。cancel は表示しない。
- cancel された処理の結果は UI に反映しない。
- 状態は enum または構造化された形で表現し、Bool の組み合わせにしない。

## 5. 非機能・設計要件

### 5.1 アーキテクチャ

- View / Observable Model / Repository / API Client を分離する。
- Observable Model は画面単位で存在する。
- Observable Model が状態と副作用、つまり非同期処理を管理する。
- View は状態の描画とユーザー入力のトリガーに限定する。
- API レスポンス DTO と UI 用 Model を分ける。
- API 依存を差し替え可能にし、DI する。
- 画像ロード依存も差し替え可能にし、Preview / Test で Mock を利用できるようにする。
- 初期実装は unauthenticated API を利用するが、将来的な認証機能追加に備えて API Client の構造を閉じすぎない。
- ViewModel パターンに依存しない設計にする。

### 5.2 状態管理

- `@Observable` な Observable Model が UI 状態を保持する。
- UI 状態を保持する Observable Model は原則として `@MainActor` に隔離する。
- ナビゲーション状態は UI 状態の一部として扱い、typed route によって表現する。

### 5.3 非同期処理

- async/await を使って API 呼び出しをする。
- Observable Model が Task を管理する。
- 不要な処理は cancel する。
- Task cancellation は協調的である前提で設計する。キャンセルしただけで処理が自動停止するとはみなさず、キャンセル確認とキャンセル後の UI 反映防止を実装する。
- View のライフサイクルと Task のキャンセルが整合している。
- `.task` または `.task(id:)` と Model 内 Task 管理を適切に使い分ける。
- actor isolation と Sendable の制約を満たし、strict concurrency の警告やエラーを残さない。
- actor 境界や Task 境界をまたぐ DTO / UI 用 Model / Error 型は `Sendable` を意識して設計する。
- `@unchecked Sendable` は原則として使用しない。必要な場合は理由を明確にする。

### 5.4 debounce

- 検索入力後、一定時間待ってから API を呼ぶ。
- 途中入力で前の待機処理がキャンセルされる。
- 古い検索結果が UI に反映されない。

### 5.5 エラー処理

- ネットワークエラーを扱える。
- HTTP エラーを扱える。
- rate limit は HTTP エラーとして扱える。
- デコードエラーを扱える。
- エラー時に retry できる。
- cancel はエラーとして扱わない。

### 5.6 ナビゲーション

- 画面遷移は `NavigationStack` を使用して実装する。
- `NavigationView` は使用しない。
- ナビゲーションはデータ駆動で表現し、`NavigationLink(value:)` と `.navigationDestination(for:)` を基本にする。
- 遷移状態は `Hashable` な typed route の配列で保持する。
- 型消去された `NavigationPath` は、異種ルートの永続化やより複雑な deep link 対応が必要になった場合に検討する。
- route には画面構築に必要な最小限の識別子を保持し、API レスポンス DTO や大きな UI Model を直接保持しない。
- `.navigationDestination(for:)` は `List` や `LazyVStack` などの lazy container の内側に置かず、`NavigationStack` から常に解決できる位置に定義する。
- 独自 Coordinator / Router は初期実装では採用しない。deep link、認証フロー、タブ構成、iPad 対応などで必要性が出た場合に導入を検討する。
- iPhone 向けの初期実装は `NavigationStack` を基本とする。iPad の複数カラム UI が必要になった場合は `NavigationSplitView` を検討する。

### 5.7 画像ロード / キャッシュ

- 画像ロードは再利用可能な Avatar 表示コンポーネントを用意し、画面ごとに ad hoc に実装しない。
- 生の `AsyncImage` だけに依存せず、画像ロードとキャッシュの境界を差し替え可能にする。
- 画像取得には `URLSession` と `URLCache` を利用し、HTTP キャッシュヘッダーを尊重する。
- 画像用の `URLSessionConfiguration` / `URLCache` は API 用通信と分離可能な構造にする。
- 画像キャッシュはメモリとディスクの両方を利用できる設計にする。
- 画像ロードの共有状態を持つ場合は actor などで隔離し、strict concurrency を満たす。

## 6. Preview 要件

- SwiftUI Preview は `#Preview` マクロを使用する。
- Preview では Repository / API Client を Mock に差し替え、ネットワーク通信を発生させない。
- 画像ローダーも Mock に差し替え、ネットワーク通信なしで成功 / loading / failure の表示を確認できるようにする。
- loading / empty / error / loaded など主要な UI 状態を Preview で確認できるようにする。
- ページング中、次ページエラー、refresh 中など、一覧画面の代表的な中間状態も Preview 対象にする。
- Preview 用 Mock はテスト用 Mock と責務を近づけつつ、見た目確認に必要なデータを簡単に用意できる構造にする。
- 非同期処理、cancel、debounce の正しさは Preview ではなく Swift Testing で検証する。

## 7. テスト要件

- Swift Testing を使用する。
- Observable Model がテスト可能な構造になっている。
- Repository をモックに差し替えられる。
- debounce や Task.sleep を安定して検証できるよう、必要に応じて Clock を注入できる。
- API Client または Repository をスタブ化し、ネットワークに依存しないテストを書ける。
- Preview 用 Mock と同じ抽象化で Repository / API Client を差し替えられる。
- 画像ローダーも Mock に差し替え、ネットワークに依存しない Preview / Test を書ける。
- MainActor 上の状態更新を検証できる。
- strict concurrency に反する実装を残さない。
- 以下をテストできる。
  - 初回ロード成功 / 失敗
  - ページング成功 / 失敗
  - debounce が効いている
  - cancel 時に状態が壊れない

## 8. 完成条件

- 検索、リポジトリ詳細、Issue / Pull Request 一覧、Issue / Pull Request 詳細のフローが動く。
- debounce と cancel が正しく動作する。
- ページングが安定して動く。
- Pull to Refresh が正しく動く。
- loading / empty / error / loaded がすべて表現されている。
- 初回ロード、ページングロード、refresh が区別されている。
- avatar 画像の placeholder / fallback / cache が機能している。
- 非同期処理の競合で UI が壊れない。
- strict concurrency の警告やエラーが残っていない。


## その他
- 複雑な検索クエリの構築とそのUI
- 検索履歴の保存
- 検索条件の保存
- 宣言型ナビゲーション, DeepLink
- 初回のハイライトチュートリアルの実装
- Github Auth, keychain, ログイン・ログアウト 有料機能
- オフライン時の表示
- パフォーマンス面での、同じクエリ検索の時間キャッシュ
- 画像キャッシュや表示の最適化
- レスポンシブ対応
- WebViewの埋め込み
- バックグラウンド更新（端末内のデータの最新化）、差分通知, in-flight request deduplication
- テスト、E2Eテスト
- stale-while-revalidate
