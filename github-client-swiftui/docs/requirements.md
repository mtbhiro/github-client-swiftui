# 要求定義書

## 1. 概要

このプロジェクトは、SwiftUI で実装する iOS 向け GitHub クライアントである。
ユーザーはリポジトリを検索し、リポジトリ詳細、Issue / Pull Request 一覧、Issue / Pull Request 詳細を確認できる。GitHub OAuth Device Flow による認証にも対応し、認証済みユーザーは高い API レート制限の恩恵を受けられる。

本ドキュメントはプロジェクト全体の要求定義である。各機能の詳細仕様は `docs/requirements/` 配下の個別 PRD を参照する。

## 2. 開発前提

### 2.1 対象・採用技術

- 対象 OS は iOS 17 以降とする。
- Swift 6 を使用する。
- strict concurrency を遵守する。
- UI は SwiftUI で実装する。
- 状態管理には SwiftUI Observation の `@Observable` を使用する。
- `ObservableObject` / `@Published` は原則として採用しない。
- 非同期処理は Swift Concurrency の async/await と Task を使用する。
- テストは Swift Testing を主に使用する。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` を設定済み。モジュール内の型・関数はデフォルトで `@MainActor` に隔離される。

### 2.2 GitHub API

- GitHub REST API を利用する。未認証・認証済みの両方に対応する。
- 認証済みの場合は `AuthenticatedHttpClient` が Bearer トークンを自動付与する。
- rate limit を考慮し、HTTP エラーとして扱えるようにする。rate limit の残量は設定画面で可視化する。
- ページングは GitHub API のページ指定またはレスポンスヘッダーを扱える形で設計する。
- Issue と Pull Request の判定は API レスポンス上の Pull Request 情報の有無で行う。

### 2.3 現在のスコープ外

- iPad 向けの複数カラム UI は現時点では必須にしない。
- 外部画像ライブラリは採用しない。必要になった場合は要件を整理してから検討する。
- 永続保存を前提にした独自画像 DB は採用しない。

## 3. 機能要件

### 3.1 リポジトリ検索

> 詳細仕様: `docs/requirements/repository-search.md`

- キーワードでリポジトリ検索ができる。
- 入力に debounce（300ms）が効いている。
- 新しい検索時に前のリクエストがキャンセルされる。
- 検索中は loading 表示を出す。
- 結果が空なら empty 表示を出す。
- エラー時は error 表示を出し、retry できる。rate limit エラーは専用の表示を出す。
- 検索結果をタップするとリポジトリ詳細画面へ遷移できる。

#### 検索クエリビルダー

- 以下の qualifier で検索条件を絞り込める。
  - `language` — プログラミング言語
  - `stars` — スター数の範囲（min / max）
  - `pushed` — 最終プッシュ日の範囲（before / after / between）
  - `topic` — トピック（複数指定可）
  - `in` — 検索対象（name / description / readme / topics）
- ソート条件を指定できる（stars / updated、asc / desc）。
- 適用中の条件はチップ形式で表示され、個別に削除できる。

#### 検索条件の永続化

> 詳細仕様: `docs/requirements/search-condition-persistence.md`

- qualifier とソート条件を UserDefaults に保存し、アプリ再起動時に復元する。
- キーワードは保存対象外とする。
- すべての qualifier がデフォルトに戻ったら保存データを自動削除する。
- 保存データの破損時はデフォルト値にフォールバックする。

#### 検索結果キャッシュ

> 詳細仕様: `docs/requirements/repository-search-cache.md`

- 同一クエリ（query + sort + page）の検索結果をメモリ内 LRU キャッシュに保持する（最大 100 エントリ）。
- キャッシュヒット時は API を呼ばずに即座に結果を返す。
- Pull to Refresh 時にキャッシュを無効化して API から再取得する。
- TTL による自動失効は行わない。プロセス終了または明示的なリフレッシュでクリアされる。

#### ページング

- スクロールで次ページを取得できる（1 ページ 30 件、最大 1000 件）。
- 次ページ取得中はフッターに loading 表示を出す。
- 多重リクエストが発生しない。
- 最終ページで止まる。
- 次ページエラー時は一覧を保持したまま retry できる。

#### Pull to Refresh

- Pull to Refresh ができる。
- Refresh 時にキャッシュが無効化され、API から再取得される。
- Refresh 中は専用の loading 状態になる。
- Refresh 後にページング状態が正しく復元される。

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

### 3.6 GitHub 認証（OAuth Device Flow）

> 詳細仕様: `docs/requirements/github-auth.md`

- GitHub OAuth Device Flow による認証ができる。
- 設定画面からログイン・ログアウトができる。
- ログインフローでは device code を取得し、ユーザーコード（XXXX-XXXX 形式）と認証 URL を表示する。
- ユーザーが GitHub 上で認可するまでポーリングで待機する。
- 取得したアクセストークンは Keychain に安全に保存する。
- アプリ起動時に Keychain からトークンを自動復元する。
- 認証済みの場合、API リクエストに Bearer トークンを自動付与する。
- 設定画面にユーザープロフィール（avatar / login / name）を表示する。プロフィールはキャッシュし、起動時にバックグラウンドで同期する。
- API から 401 が返った場合は自動的にログアウトする。
- rate limit の残量（limit / remaining）を設定画面に表示する。未認証は 60 req/h、認証済みは 5,000 req/h。
- ログアウト時は確認ダイアログを表示する。
- Device Flow のエラー状態（設定エラー・ネットワークエラー・アクセス拒否・トークン期限切れ）を適切に処理する。

### 3.7 ブックマーク

- リポジトリをブックマークに追加・削除できる。
- ブックマーク一覧画面からリポジトリ詳細への遷移ができる。
- ブックマーク状態はアプリ内で保持する。

### 3.8 Deep Link

> 詳細仕様: `docs/requirements/deeplink.md`

- カスタム URL スキーム `githubclient://` によるディープリンクに対応する。
- 対応ルート:
  - `githubclient://repo/{owner}/{name}` — リポジトリ詳細を開く
  - `githubclient://repo/{owner}/{name}/issues` — Issue 一覧を開く
- NavigationStack のパスを自動構築し、正しい画面階層で表示する。
- 不正な URL は静かに無視する。

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
- HttpClient プロトコルを基盤にし、認証時は AuthenticatedHttpClient でラップする。
- ViewModel パターンに依存しない設計にする。

### 5.2 状態管理

- `@Observable` な Observable Model が UI 状態を保持する。
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` により、Observable Model はデフォルトで `@MainActor` に隔離される。
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

- 検索入力後、一定時間（300ms）待ってから API を呼ぶ。
- 途中入力で前の待機処理がキャンセルされる。
- 古い検索結果が UI に反映されない。

### 5.5 エラー処理

- ネットワークエラーを扱える。
- HTTP エラーを扱える。
- rate limit は HTTP エラーとして扱え、専用の UI 状態で表現する。
- デコードエラーを扱える。
- エラー時に retry できる。
- cancel はエラーとして扱わない。
- 401 Unauthorized は認証トークンの失効として扱い、自動ログアウトする。

### 5.6 ナビゲーション

- 画面遷移は `NavigationStack` を使用して実装する。
- `NavigationView` は使用しない。
- ナビゲーションはデータ駆動で表現し、`NavigationLink(value:)` と `.navigationDestination(for:)` を基本にする。
- 遷移状態は `Hashable` な typed route の配列で保持する。
- route には画面構築に必要な最小限の識別子を保持し、API レスポンス DTO や大きな UI Model を直接保持しない。
- `.navigationDestination(for:)` は `List` や `LazyVStack` などの lazy container の内側に置かず、`NavigationStack` から常に解決できる位置に定義する。
- タブ構成は Search / Bookmarks / Settings の 3 タブで構成する。
- AppCoordinator がタブごとのナビゲーション状態を管理し、ディープリンクからのパス構築にも対応する。
- typed route はタブごとに定義する（SearchRoute / BookmarksRoute / SettingsRoute）。
- iPhone 向けの実装は `NavigationStack` を基本とする。iPad の複数カラム UI が必要になった場合は `NavigationSplitView` を検討する。

### 5.7 画像ロード / キャッシュ

- 画像ロードは再利用可能な Avatar 表示コンポーネントを用意し、画面ごとに ad hoc に実装しない。
- 生の `AsyncImage` だけに依存せず、画像ロードとキャッシュの境界を差し替え可能にする。
- 画像取得には `URLSession` と `URLCache` を利用し、HTTP キャッシュヘッダーを尊重する。
- 画像用の `URLSessionConfiguration` / `URLCache` は API 用通信と分離可能な構造にする。
- 画像キャッシュはメモリとディスクの両方を利用できる設計にする。
- 画像ロードの共有状態を持つ場合は actor などで隔離し、strict concurrency を満たす。

### 5.8 認証・セキュリティ

- アクセストークンは Keychain に保存する。UserDefaults や平文保存は行わない。
- GitHubAuthState がグローバルな認証状態を管理し、トークンの有無に応じて API クライアントの振る舞いが切り替わる。
- RateLimitObserver が API レスポンスヘッダー（X-RateLimit-*）を監視し、設定画面で可視化する。

### 5.9 永続化

- 認証トークン: Keychain（KeychainStorage）
- ユーザープロフィールキャッシュ: UserDefaults
- 検索条件（qualifier / sort）: UserDefaults（RepositorySearchConditionStore）
- 検索結果キャッシュ: メモリ内 LRU キャッシュ（プロセス終了でクリア）

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
  - 検索クエリビルダーの組み立てが正しい
  - 検索条件の永続化と復元が正しい
  - 検索結果キャッシュの LRU 動作が正しい
  - Device Flow のポーリング・タイムアウト・キャンセルが正しい
  - 認証状態のライフサイクル（トークン保存・復元・401 検知・ログアウト）が正しい
  - AuthenticatedHttpClient の Bearer トークン付与と 401 検知が正しい
  - ディープリンクの URL パースとルート構築が正しい

## 8. 完成条件

- 検索、リポジトリ詳細、Issue / Pull Request 一覧、Issue / Pull Request 詳細のフローが動く。
- 検索クエリビルダー（qualifier / sort）が正しく動作し、チップ表示される。
- 検索条件がアプリ再起動後に復元される。
- 検索結果キャッシュにより同一クエリの再検索が即座に返る。
- debounce と cancel が正しく動作する。
- ページングが安定して動く。
- Pull to Refresh が正しく動く。
- loading / empty / error / loaded がすべて表現されている。
- 初回ロード、ページングロード、refresh が区別されている。
- avatar 画像の placeholder / fallback / cache が機能している。
- 非同期処理の競合で UI が壊れない。
- strict concurrency の警告やエラーが残っていない。
- GitHub OAuth Device Flow でログイン・ログアウトができる。
- 認証済み API リクエストに Bearer トークンが付与される。
- rate limit の残量が設定画面に表示される。
- ディープリンク（`githubclient://repo/{owner}/{name}` 等）で正しい画面が開く。
- ブックマーク一覧からリポジトリ詳細へ遷移できる。

## 9. 個別 PRD 一覧

各機能の詳細な仕様（画面定義・状態遷移・AC・テスト要件）は以下の個別 PRD に記載されている。

| ファイル | 機能 |
|---|---|
| `docs/requirements/repository-search.md` | リポジトリ検索（qualifier / sort / チップ表示） |
| `docs/requirements/search-condition-persistence.md` | 検索条件の永続化 |
| `docs/requirements/repository-search-cache.md` | 検索結果の LRU メモリキャッシュ |
| `docs/requirements/github-auth.md` | GitHub OAuth Device Flow 認証 |
| `docs/requirements/deeplink.md` | カスタム URL スキームによるディープリンク |

## 10. 今後の検討事項

以下は現時点で未実装であり、必要に応じて PRD を起こして開発する。

- 検索履歴の保存
- 初回のハイライトチュートリアル
- オフライン時の表示
- レスポンシブ対応（iPad 複数カラム UI）
- WebView の埋め込み
- バックグラウンド更新（端末内データの最新化）・差分通知・in-flight request deduplication
- E2E テスト
- stale-while-revalidate
