# DeepLink 仕様書

> 本書は外部からアプリを起動して特定の画面を直接開く「deeplink」機能の仕様を定義する。`requirements.md` の §2.3「deep link は初期実装では必須にしない」を解除し、§5.6 のナビゲーション方針を拡張する位置付け。本書と矛盾する場合は本書を優先する。プロジェクト全体方針（`@Observable` 採用、`NavigationStack` ベースのデータ駆動ナビゲーション、Swift 6 strict concurrency、`AppCoordinator` による path 一元管理）は `CLAUDE.md` / `requirements.md` を参照し、本書では再掲しない。

## 1. 目的と背景

- 外部（Safari・他アプリ・ホーム画面のショートカット・将来的に通知やメール本文など）からアプリを起動した際、ユーザーが目的の画面に **直接到達できる** ようにする。
- 想定ユーザーは、Slack や Safari で GitHub のリポジトリ URL を共有された開発者が、本アプリで対応する画面を即座に開きたい場面など。
- 既存ナビゲーションは `AppCoordinator` がタブごとに `[Hashable]` の typed route を一元管理しており、deeplink を path 配列の組み立てに落とし込みやすい構造になっている。本フェーズではこの構造に **URL → typed route 列への変換境界** を追加することで、最小コストで deeplink を実現する。

## 2. スコープ

### 2.1 対象

- 以下 2 種類の deeplink を扱う。
  - **リポジトリ詳細を開く**: `githubclient://repo/{owner}/{name}`
  - **リポジトリの Issue 一覧を開く**: `githubclient://repo/{owner}/{name}/issues`
- 受信時に `AppCoordinator.selectedTab` を `.search` に切り替え、`AppCoordinator.searchPath` を deeplink の経路で組み立て直す。
- アプリ未起動・バックグラウンド復帰のいずれの状態からも、上記 URL によって対応画面に到達できる。
- 不正な URL（スキームは一致するが path が解釈できない、`owner` / `name` が空、等）の受信時は **静かに無視する**（既存状態を変えない）。
- URL Scheme（`githubclient://`）のアプリ側登録と、SwiftUI の `onOpenURL` 経路での受信。

### 2.2 対象外

以下は本フェーズでは扱わない。§10 に将来課題として再掲する。

- Universal Links（`https://...` 形式）の対応、`apple-app-site-association` の配信、Associated Domains の構成。
- リポジトリ詳細以外の deeplink（Issue 詳細、ユーザープロフィール、検索結果ページ、ブックマーク、設定など）。
- deeplink で開いたあとに「閉じる」を押すと外部アプリに戻る等の連携機能。
- deeplink 経由かどうかでナビゲーションスタックの「戻る」挙動を切り替える機能（戻り先はあくまで検索タブのルート＝検索画面とする）。
- deeplink を受信したことを示す UI フィードバック（トースト・ログ・成功画面など）。
- 受信した URL の履歴保存・最近開いた deeplink の表示。
- deeplink で渡された情報を Universal Clipboard や Handoff から取得する経路。
- リポジトリ存在チェックを deeplink 受信時に行うこと（存在しないリポジトリでも詳細画面に遷移し、画面側の error 状態で扱う）。
- 認証付き API への deeplink、private リポジトリ向け遷移。
- iPad の複数カラム UI 向け deeplink。
- deeplink で渡される識別子の i18n / 大文字小文字正規化。GitHub の owner / repo は大文字小文字を区別しないが、本フェーズではアプリ側で正規化しない（受信した文字列をそのまま `GitHubRepoFullName` に詰める）。

## 3. ユーザーストーリーと受け入れ条件

### US-1: リポジトリ詳細を deeplink で開く

外部アプリの利用者として、`githubclient://repo/{owner}/{name}` 形式の URL をタップしたとき、本アプリが起動して該当リポジトリの詳細画面に直接到達したい。

- AC-1.1 アプリ未起動の状態で `githubclient://repo/apple/swift` を開くと、アプリが起動し、検索タブが選択された状態で、リポジトリ詳細画面（`owner=apple, name=swift`）が表示される。検索画面 → リポジトリ詳細画面の 2 階層スタックとして観測できる。
- AC-1.2 アプリがバックグラウンドにある状態（任意のタブ / 任意のスタック状態）で同 URL を受信すると、`selectedTab` が `.search` に切り替わり、`searchPath` は `[.repositoryDetail(apple/swift)]` で **置換** される。受信前の `searchPath` / `bookmarksPath` / `settingsPath` の中身は破棄される。
- AC-1.3 詳細画面で「戻る」操作を行うと、検索画面（`searchPath` が空）に戻る。これは検索画面から通常通り検索して詳細に遷移した後に戻る挙動と等価。
- AC-1.4 URL に含まれる owner / name の文字列はそのまま `GitHubRepoFullName` の `ownerLogin` / `name` として使用される（大文字小文字変換・トリム等の正規化を行わない）。
- AC-1.5 URL を受信した時点で詳細画面の表示が始まる。GitHub API へのリクエスト（リポジトリ存在確認）は deeplink 受信ハンドラ内では行わず、画面遷移後に詳細画面の通常ロードフローで発火する。

### US-2: リポジトリの Issue 一覧を deeplink で開く

外部アプリの利用者として、`githubclient://repo/{owner}/{name}/issues` 形式の URL をタップしたとき、本アプリが起動して該当リポジトリの Issue 一覧画面に直接到達したい。

- AC-2.1 アプリ未起動の状態で `githubclient://repo/apple/swift/issues` を開くと、アプリが起動し、検索タブが選択された状態で、リポジトリ詳細画面 → Issue 一覧画面の 3 階層スタックが構築され、最前面に Issue 一覧画面が表示される。
- AC-2.2 アプリがバックグラウンドにある状態で同 URL を受信すると、`selectedTab` が `.search` に切り替わり、`searchPath` は `[.repositoryDetail(apple/swift), .issueList(apple/swift)]` で **置換** される。受信前の path の中身は破棄される。
- AC-2.3 Issue 一覧画面で「戻る」操作を行うと、リポジトリ詳細画面に戻る。さらに「戻る」を行うと検索画面に戻る。これは検索 → リポジトリ詳細 → Issue 一覧と通常導線でたどった後の戻り操作と等価。
- AC-2.4 URL に含まれる owner / name の文字列はそのまま `GitHubRepoFullName` に使用される（AC-1.4 と同じ）。

### US-3: deeplink を常に既知の状態から始める

deeplink 利用者として、URL を開いた瞬間にどの画面がどの順序で開くかが予測可能でありたい。

- AC-3.1 deeplink の受信は **現在のナビゲーション状態に依存しない**。受信前にどのタブを開いていても、どの画面まで push していても、deeplink を解決した結果のスタックは AC-1.2 / AC-2.2 の通り **置換** された状態になる。
- AC-3.2 ただし詳細画面 / Issue 一覧画面の内部状態（API ロード結果・スクロール位置等）は deeplink 起動の都度新規に構築する。バックグラウンド復帰前に同じリポジトリの詳細を開いていた場合でも、その状態を流用することは要件として保証しない。

### US-4: 不正な URL は静かに無視する

- AC-4.1 スキームが `githubclient://` であっても、以下のいずれかに該当する URL は **無視** する。アプリ起動済みなら現在のナビゲーション状態を **変更しない**。アプリ未起動から起動された場合は、deeplink が無い通常起動と同じ初期状態（検索タブ / `searchPath` 空 / idle）で立ち上がる。
  - host が `repo` 以外。
  - path 階層数が 2（`/owner/name`）でも 3（`/owner/name/issues`）でもない。
  - path 階層数が 3 で 3 階層目が `issues` 以外。
  - `owner` または `name` が空文字（連続スラッシュ・末尾スラッシュ等によって空成分が生まれた場合を含む）。
  - URL のクエリ・フラグメント・余分な path セグメントが含まれる場合は、本フェーズでは **未対応として扱い、無視する**（将来拡張のために予約）。
- AC-4.2 受信した URL のスキームが `githubclient` 以外のとき、本機能は何も行わない。SwiftUI 既定の動作に委ねる。
- AC-4.3 不正 URL の受信時にユーザー向けのエラーメッセージ・トースト・アラートは表示しない。

## 4. 振る舞い仕様

### 4.1 入出力一覧

| ユーザー操作 / 入力 | 前提条件 | システム応答 / 表示 |
|---|---|---|
| `githubclient://repo/{owner}/{name}` を受信 | アプリ未起動 | アプリ起動 → 検索タブ選択 → `searchPath = [.repositoryDetail(owner/name)]` → 詳細画面表示 |
| `githubclient://repo/{owner}/{name}` を受信 | アプリ起動中（任意のタブ・スタック） | `selectedTab = .search` に切替、`searchPath` を `[.repositoryDetail(owner/name)]` で置換、`bookmarksPath` / `settingsPath` には変更を加えない |
| `githubclient://repo/{owner}/{name}/issues` を受信 | アプリ未起動 | アプリ起動 → 検索タブ選択 → `searchPath = [.repositoryDetail(owner/name), .issueList(owner/name)]` → Issue 一覧画面表示 |
| `githubclient://repo/{owner}/{name}/issues` を受信 | アプリ起動中 | `selectedTab = .search`、`searchPath` を `[.repositoryDetail(owner/name), .issueList(owner/name)]` で置換 |
| Issue 一覧画面で「戻る」 | deeplink 経由で開かれている | リポジトリ詳細画面に戻る |
| リポジトリ詳細画面で「戻る」 | deeplink 経由で開かれている | 検索画面（`searchPath` が空）に戻る |
| 不正 URL（host ≠ `repo` / path 不一致 / 空成分 / クエリ・フラグメント付き）を受信 | アプリ起動中 | 何もしない。ナビゲーション状態は不変 |
| 不正 URL を受信 | アプリ未起動 | 通常起動（検索タブ / `searchPath` 空 / idle）として立ち上がる |
| `githubclient` 以外のスキームの URL を受信 | — | 本機能の責務外、何もしない |
| deeplink 受信中にユーザーがタブを切り替え | 受信処理中 | 受信処理は同期的に完了（path 置換とタブ切替）するため競合は発生しない前提。ユーザーのタブ切替が後勝ちで反映される |

### 4.2 状態と表示

deeplink 受信は **イベント** であり画面状態としては独立しない。受信した結果として遷移するのは、既存の検索 → 詳細 → Issue 一覧の各画面で、それぞれの状態（loading / loaded / error / empty）は本書のスコープ外（各画面の PRD を参照）。本機能で観測可能な「状態変化」は次の 2 つに限定する。

| 観測項目 | deeplink 受信前 | 受信後 |
|---|---|---|
| `selectedTab` | 任意 | `.search` に置換 |
| `searchPath` | 任意 | 詳細のみなら `[.repositoryDetail(fullName)]`、Issue 一覧なら `[.repositoryDetail(fullName), .issueList(fullName)]` に置換 |
| `bookmarksPath` / `settingsPath` | 任意 | 変更なし |

### 4.3 バリデーションと異常系

#### 4.3.1 URL バリデーション規則

スキーム `githubclient` の URL に対してのみ評価を行う。以下を **すべて満たす** ものを「有効」と判定し、それ以外は §4.3.2 の異常系に分類する。

- スキーム = `githubclient`
- host = `repo`
- path セグメント数 = 2 または 3
  - 2 のとき: `[owner, name]`。いずれも空文字でない。
  - 3 のとき: `[owner, name, "issues"]`。owner / name は空文字でない。3 番目は完全一致で `issues`。
- クエリ文字列・フラグメントが存在しない
- 上記以外のパス階層・追加成分が無い

`owner` / `name` の文字列内容に対する制約は設けない（GitHub 側の命名規則を改めて検証しない。AC-1.4 / AC-2.4 で正規化もしない）。

#### 4.3.2 異常系の分類と挙動

| 分類 | 該当条件 | 挙動 |
|---|---|---|
| **non-deeplink** | スキームが `githubclient` 以外 | 本機能の責務外。SwiftUI 既定の動作に委ねる |
| **invalid** | スキームは一致するが §4.3.1 の判定に通らない | 静かに無視。ナビゲーション状態を変更しない。アプリ未起動からの起動なら通常起動と同じ初期状態にする |

### 4.4 同時受信・連続受信

- 連続して deeplink を受信した場合、受信順に `searchPath` を置換する。最後に受信した有効な URL の結果が最終状態となる。
- 受信処理は同期的（path 配列とタブの代入のみ）であり、ロックや待機は不要。

## 5. URL スキーマ仕様

### 5.1 スキーム

- アプリ側で登録する URL Scheme は `githubclient` の **1 つだけ**。
- 大文字小文字: スキーム部分は小文字固定で扱う。`GithubClient://...` 等の大文字混じり URL の扱いは iOS の `URL` 標準挙動に従う（スキーム比較は大文字小文字を区別しないため通常は許容される）。

### 5.2 URL テンプレート

| 用途 | URL テンプレート | 例 |
|---|---|---|
| リポジトリ詳細 | `githubclient://repo/{owner}/{name}` | `githubclient://repo/apple/swift` |
| Issue 一覧 | `githubclient://repo/{owner}/{name}/issues` | `githubclient://repo/apple/swift/issues` |

- `{owner}` / `{name}` は URL パスセグメントとしてエスケープされている前提（GitHub 仕様上、これらにスラッシュや空白は含まれないが、URL 上で `%2F` 等が含まれる場合は `URL.pathComponents` のデコード結果をそのまま使う）。
- パスセグメントの末尾スラッシュは許容しない（AC-4.1: 空成分が生まれるため invalid）。

### 5.3 path セグメントから typed route 列への対応

| path セグメント | 構築される `searchPath` |
|---|---|
| `[owner, name]` | `[.repositoryDetail(GitHubRepoFullName(ownerLogin: owner, name: name))]` |
| `[owner, name, "issues"]` | `[.repositoryDetail(fullName), .issueList(fullName)]`（`fullName` は両 route で同一インスタンス） |

## 6. 画面構成

### 6.1 画面一覧

deeplink 自身は画面を持たない。受信結果として表示される画面は以下の既存画面に限られる。

- **検索画面** (`RepositorySearchView`): deeplink 後に「戻る」で必ず到達するルート。
- **リポジトリ詳細画面** (`RepositoryDetailView`): `searchPath` に `.repositoryDetail` が積まれた結果として表示される。
- **Issue 一覧画面** (`IssueListView`): `searchPath` の最後に `.issueList` が積まれた結果として表示される。

### 6.2 画面ごとの構成

各画面の構成・配置要素・主要操作・状態ごとの見え方は、既存実装および将来の対応 PRD に委ねる。本書は **画面の中身を変更しない**。

## 7. データ要件

### 7.1 入力データ

- URL: `URL` 型として SwiftUI の `onOpenURL` 経由で受信される。
- 必要な情報: スキーム / host / `pathComponents`。クエリ / フラグメントは検証用に確認するが本フェーズでは使わない。

### 7.2 外部データソース

- 本機能では GitHub API を呼び出さない。リポジトリ存在チェックは行わず、画面遷移後の通常ロードフロー（詳細画面 / Issue 一覧画面）で必要なら発火する。

### 7.3 永続データ

- 永続化を行わない。直近に開いた deeplink の保存・履歴・再生機能は対象外（§2.2 / §10）。

## 8. 非機能要件

### 8.1 性能

- URL 受信から `selectedTab` / `searchPath` 反映までを **同一 main run loop tick 内** で完了する。デコード・解析処理は同期的に行い、ローカル処理 1 件あたり 50ms 以内とする。
- アプリ未起動から deeplink 経由で画面が表示されるまでの所要時間は、通常起動 + 画面遷移の合算と同等水準であること（deeplink 解析が観測可能な追加遅延を作らない）。

### 8.2 アクセシビリティ

- deeplink 受信によって表示される画面は、既存画面と同じアクセシビリティ要件（VoiceOver ラベル / Dynamic Type 追従）を満たす。deeplink 固有のアクセシビリティ追加要件は持たない。

### 8.3 信頼性

- 不正 URL を受信した場合のクラッシュ・例外スローは発生してはならない。`invalid` 分類はすべて無視として安全に終端する。
- スキーム解決が strict concurrency に違反しない（main actor 上での同期的代入のみ）。

## 9. 完了の定義

以下のすべてを満たしたとき、本機能は完了とみなす。

- §3 のすべての受け入れ条件（AC-1.1〜AC-4.3）が満たされる。
- §4.3 の異常系 2 分類（non-deeplink / invalid）すべてに対し、定義された挙動を満たす。
- §5 の URL テンプレート 2 種類が、Safari からのタップ・ホーム画面ショートカット・別アプリの URL 起動（実機の任意の手段）から、いずれも要件通りに動作する。
- §10 の検証要件のテストが Swift Testing ですべて通る。
- §8 の非機能目標を満たす（同期反映 / クラッシュ無し / strict concurrency 警告無し）。

## 10. 検証要件と AC の対応

§3 の各受け入れ条件に対し、Swift Testing で検証すべき観点を定義する。具体的なテスト設計・Mock 構造には踏み込まない。

| 検証観点 | 対応 AC |
|---|---|
| `githubclient://repo/{owner}/{name}` の解決結果が `selectedTab = .search` かつ `searchPath = [.repositoryDetail(fullName)]` になる | AC-1.1, AC-1.2 |
| 受信前の `searchPath` / `bookmarksPath` / `settingsPath` がそれぞれ仕様通り（searchPath は置換、その他は不変）になる | AC-1.2, AC-2.2 |
| owner / name の文字列が正規化なしで `GitHubRepoFullName` に詰められる | AC-1.4, AC-2.4 |
| `githubclient://repo/{owner}/{name}/issues` の解決結果が `searchPath = [.repositoryDetail(fullName), .issueList(fullName)]` になり、両 route の `fullName` が等価 | AC-2.1, AC-2.2 |
| deeplink で 2 階層 push された後に pop すると `searchPath` が空に戻る | AC-1.3 |
| deeplink で 3 階層 push された後に 2 回 pop すると `searchPath` が空に戻る | AC-2.3 |
| deeplink 受信は受信前のスタック内容に依存しない（既存スタックを保持しない） | AC-3.1 |
| 不正 URL（host ≠ repo / 階層数不一致 / 3 階層目 ≠ issues / 空成分 / クエリ・フラグメント付き）を解決すると nil / 失敗となり、`AppCoordinator` のいずれの path も `selectedTab` も変化しない | AC-4.1 |
| `githubclient` 以外のスキームの URL に対して、本機能の解析関数が呼ばれても何もしない（または非対象として早期 return する） | AC-4.2 |
| 不正 URL 受信時にエラー表示・ログ・トーストが発火しない | AC-4.3 |
| URL → `[SearchRoute]` 変換関数が **純粋関数**（外部状態に依存しない / 副作用を持たない）として実装され、同じ URL 入力に対して同じ出力を返す | §5.3 |
| `URL` → `[SearchRoute]` 変換の主要なケース（正常 2 種 + 不正系 5 種以上）を網羅した単体テストが揃う | §4.3.1, §5.3 |
| 同期反映性能（受信から path 反映までが同一 main run loop tick 内に完了する）を保証する観点 | §8.1 |

## 11. 将来課題

§2.2 の対象外項目のうち、優先度の高いものから列挙する。

1. Universal Links（`https://github.com/{owner}/{name}` 等の Web URL からの直接遷移）対応。Associated Domains 構成と `apple-app-site-association` 配信が必要。
2. Issue 詳細画面への deeplink（`githubclient://repo/{owner}/{name}/issues/{number}` 等）。
3. ブックマーク画面・設定画面など他タブへの deeplink。
4. クエリ文字列やフラグメントの解釈（例: タブ初期化条件、ハイライト位置、検索キーワード prefill）。
5. owner / name の大文字小文字正規化、GitHub 公式仕様に従った重複排除。
6. deeplink 経由で開いた事実を画面 UI で示すフィードバック。
7. deeplink 起動時に渡された情報の履歴保存・再生。

## 12. 参照

- `github-client-swiftui/docs/requirements.md`（全体要求定義。§2.3 / §5.6 を本書で更新）
- `github-client-swiftui/docs/requirements/repository-search.md`（検索 → 詳細遷移の AC-6.1 / AC-6.2 と整合）
- `github-client-swiftui/docs/guide/navigation-guide.md`（stack-based `NavigationStack` と deeplink の相性）
- `github-client-swiftui/CLAUDE.md`（プロジェクト前提・実装規約）
- 関連既存実装（参照のみ。設計指示はしない）
  - `github-client-swiftui/Common/Navigation/AppCoordinator.swift`
  - `github-client-swiftui/Common/Navigation/AppRoute.swift`
  - `github-client-swiftui/Common/Model/GitHubRepoFullName.swift`
  - `github-client-swiftui/RootView.swift`
  - `github-client-swiftui/github_client_swiftuiApp.swift`
- Apple Developer: Defining a custom URL scheme for your app — https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app
- Apple Developer: `View.onOpenURL(perform:)` — https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)
