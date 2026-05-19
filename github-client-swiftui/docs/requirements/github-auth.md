# GitHub 認証 仕様書

> 本書は GitHub OAuth Device Flow を用いたログイン機能の仕様を定義する。`requirements.md` §2.2「初期実装では unauthenticated」「将来的な認証機能追加を前提に token 付与や認証ヘッダー差し替えができる構造にする」を本書で **解除・拡張** する位置付け。本書と矛盾する場合は本書を優先する。プロジェクト全体方針（`@Observable` 採用、`NavigationStack` ベースのデータ駆動ナビゲーション、Swift 6 strict concurrency、画像ローダーの差し替え可能性、debounce / cancel の枠組み、HTTP エラー扱い）は `CLAUDE.md` / `requirements.md` を参照し、本書では再掲しない。

## 1. 目的と背景

- 本機能の目的は、**「ログイン機能」と「認証状態の管理」を題材として学習する** ことにある。プロダクションサービスとして公開する想定ではなく、開発者自身の GitHub アカウントを用いた学習・検証用途を主とする。
- 同時に副次効果として、GitHub API の **レート制限が 60 req/h（unauthenticated）から 5000 req/h（authenticated）に緩和** され、既存の検索・詳細・Issue 一覧などの実用性が向上する。
- 採用方式は **GitHub OAuth Device Flow**。Client Secret 不要・サーバー不要・iOS だけで完結し、「フロー（ブラウザ往復・polling）」「トークンの安全な保存（Keychain）」「認証状態の起動時復元」「API クライアントへの認証ヘッダ注入」「401 時の自動ログアウト」「ログアウト」を一通り扱える。
- 既存 API クライアント (`HttpClient` / `URLSessionHttpClient`) は `HttpRequest.headers` で任意ヘッダを注入できるため、認証ヘッダ差し替え境界を新設するコストが低い。本機能はこの構造の上に認証層を追加する位置付けとする。

## 2. スコープ

### 2.1 対象

- **Device Flow による OAuth 認証**
  - device code 取得 → ユーザーコード表示 → ユーザーがブラウザで認可 → polling で access token 取得 → Keychain 保存。
- **認証状態の管理**
  - アプリ起動時に Keychain から token を読み出し、`@Observable` なグローバル認証状態を復元する。
  - 認証状態は「未ログイン / Device Flow 進行中 / ログイン済み」を表現する。
- **ログイン UI と認証確認**
  - Settings タブの設定画面に「GitHub にログイン」「ログアウト」操作と、ログイン後のプロフィール表示（avatar / `login` / `name`）を置く。プロフィール表示は **「ログインできていること」をユーザーが目視確認するための主たる手段** とする。
  - Device Flow 進行中の専用画面でユーザーコード・認可 URL・「ブラウザで開く」「コードをコピー」「キャンセル」を提示し、polling 状態を表示する。
- **既存 API への token 注入**
  - ログイン済みのとき、すべての GitHub API 呼び出し（`ApiHost == .github` のリクエスト全件）に `Authorization: Bearer <token>` ヘッダを付与する。
- **レート制限の可視化**
  - Settings 画面に「現在のレート制限上限 / 残り回数」を表示する（未ログイン時は 60、ログイン時は 5000 であることが観測できる）。
- **401 失効検知**
  - 認証付きリクエストで 401 を受けたら自動的にログアウト処理を行い、Settings 画面のログインボタンが再表示される。
- **ログアウト**
  - Keychain からトークンを破棄し、認証状態を未ログインに戻す。
- **Client ID の安全な配置**
  - Client ID は `.xcconfig` ファイル経由で `Info.plist` に注入し、`.xcconfig` 本体は `.gitignore` で git 管理対象外にする。テンプレートだけリポジトリに残す。

### 2.2 対象外

以下は本フェーズでは扱わない。§10 に将来課題として再掲する。

- **認証必須機能の追加**（「自分のリポジトリ一覧」「自分の Issue 一覧」「starred / following」「private リポジトリ専用 UI」など）。本フェーズはログインできていることを Settings 画面のプロフィール表示で確認するところまでとする。
- OAuth App ではなく **GitHub App** を使う認証フロー。
- **PKCE 付き Web Application Flow**、SFSafariViewController / `ASWebAuthenticationSession` ベースの redirect 認証フロー。
- **Personal Access Token (PAT) の手入力**による認証経路。
- **複数アカウントの同時保持・切替**。本フェーズは「現在ログインしているアカウントは最大 1 件」とする。
- **scope の動的選択**。要求 scope は実装時に固定する（§7.2）。
- **token refresh**（GitHub OAuth Device Flow の access token は refresh token を発行しないため）。
- **`X-RateLimit-Reset` を用いたカウントダウン表示**。レート制限の可視化は「上限 / 残り回数」の数値のみで、解除予定時刻のリアルタイム表示は行わない。
- **bookmark / 既存検索結果の認証連動した再フェッチ**。ログイン / ログアウト時に既存画面の表示中データを自動再取得することは要件としない。次回ロード時から新しい認証状態が適用されればよい。
- **device code 期限切れ後の自動再開**。期限切れ時は専用画面を閉じ、ユーザーに再開操作を求める。
- **多言語対応 (i18n)**。本フェーズの UI 文言は日本語単一とする。
- **生体認証 / アプリパスコードによる Keychain アクセス保護**。Keychain への保存自体は行うが、`SecAccessControl` でユーザー認証を要求する設定は本フェーズでは行わない。
- **Sign in with Apple、Firebase Auth など他社認証基盤**。

## 3. ユーザーストーリーと受け入れ条件

### US-1: GitHub アカウントでログインする

開発者として、設定画面からブラウザ経由で自分の GitHub アカウントに認可を与え、本アプリで認証済み状態として使えるようにしたい。

- AC-1.1 未ログイン状態の Settings 画面には「GitHub にログイン」ボタンが表示される。ボタンタップで Device Flow の **コード表示画面** に遷移する。
- AC-1.2 コード表示画面に遷移した時点で device code 取得 API が 1 回だけ発火し、応答が返るまでの間は **loading 表示**（プログレスインジケータ）が画面中央に表示される。
- AC-1.3 device code 取得に成功したら、画面中央に **8 文字のユーザーコード**（GitHub の表記に従い、4-4 のハイフン区切りで `XXXX-XXXX` 形式）と、ユーザーが認可ページを開くための **認可 URL**（`https://github.com/login/device`）が表示される。同時に「ブラウザで開く」「コードをコピー」「キャンセル」の 3 操作が有効化される。
- AC-1.4 「ブラウザで開く」をタップすると、認可 URL が外部ブラウザ（Safari）で開かれる。アプリは画面遷移せずコード表示画面に留まり、polling を継続する。
- AC-1.5 「コードをコピー」をタップすると、ユーザーコードがクリップボードにコピーされる。
- AC-1.6 device code 取得直後から、access token 取得 API のポーリングが開始される。ポーリング間隔は GitHub API のレスポンス `interval` 秒（既定 5 秒）を初期値とし、サーバーから `slow_down` を受けたら +5 秒する。コード表示画面が表示されている間、ポーリング中は **「認可を待っています…」相当のメッセージ** と進行表示が常時表示される。
- AC-1.7 ユーザーが外部ブラウザで認可を完了し、ポーリングが成功して access token を取得した時点で、token が Keychain に保存され、認証状態が「ログイン済み」に更新される。コード表示画面は自動的に閉じ、Settings 画面に戻る。
- AC-1.8 ログイン直後の Settings 画面には、`GET /user` で取得した **自分のプロフィール**（avatar / `login` / `name`）が表示される。`name` が null の場合は表示しない。「ログイン」ボタンは「ログアウト」ボタンに置き換わる。**プロフィールが表示されていること自体が、「ログインに成功した」ことのユーザーから観測可能な確認手段である**。
- AC-1.9 「キャンセル」をタップした場合、polling は停止し、Settings 画面に戻る。認証状態は未ログインのまま維持される（取得済みの device code は破棄）。

### US-2: ログインで API のレート制限を緩和する

ログイン中の開発者として、レート制限の緩和を享受し、既存の検索・詳細・Issue 一覧などの GitHub API 呼び出しを実用的に使いたい。

- AC-2.1 ログイン済み状態で発火される GitHub API リクエスト（host = `api.github.com`）はすべて `Authorization: Bearer <token>` ヘッダを含む。
- AC-2.2 未ログイン状態で発火される GitHub API リクエストは `Authorization` ヘッダを含まない。
- AC-2.3 認証ヘッダの付与・非付与の切り替えは、ログイン / ログアウト後 **次回以降の API リクエスト** から有効になる。進行中の API リクエストや既に表示済みのデータに対する自動再フェッチは行わない。

### US-3: レート制限の緩和を可視化する

学習目的の開発者として、認証によってレート制限が変わることを画面上で確認したい。

- AC-3.1 Settings 画面に「レート制限」セクションがあり、**上限 / 残り回数** を表示する。
- AC-3.2 値の取得元は、直近に成功した任意の GitHub API レスポンスの `X-RateLimit-Limit` / `X-RateLimit-Remaining` ヘッダとする。値が取得済みでないあいだは「未取得」と表示する。
- AC-3.3 未ログイン時に値が取得できた場合は上限 60、ログイン時に値が取得できた場合は上限 5000 が観測できる（上限は GitHub 仕様に依存し、本書では値の固定は保証しない）。
- AC-3.4 ログイン状態が変わった瞬間は値を保持せず、`未取得` 表示にリセットする。次の API 成功時に再表示される。

### US-4: ログアウトする

ログイン中の開発者として、必要なときに Keychain から token を破棄し、未ログイン状態に戻したい。

- AC-4.1 ログイン中の Settings 画面の「ログアウト」ボタンをタップすると、**確認ダイアログ**（「ログアウトしますか？」/「ログアウト」「キャンセル」）が表示される。
- AC-4.2 「ログアウト」を選択すると、Keychain からトークンが削除され、認証状態が未ログインに更新される。プロフィール表示はクリアされ、ログインボタンが再表示される。
- AC-4.3 「キャンセル」を選択した場合、何も起きない。

### US-5: アプリ再起動でログイン状態を復元する

開発者として、アプリを終了して再度開いたとき、ログイン状態が維持されていてほしい。

- AC-5.1 ログイン済みの状態でアプリを完全終了 → 再起動した直後、Settings 画面はログイン済み表示（プロフィールとログアウトボタン）で立ち上がる。
- AC-5.2 起動直後の `GET /user` 呼び出しでプロフィール情報を取得する。失敗（ネットワーク失敗）した場合は **Keychain のトークンと、保存済みのプロフィール（後述 §7.3）からログイン状態を維持** し、プロフィール領域はキャッシュ表示する。
- AC-5.3 起動直後の `GET /user` 呼び出しで 401 が返った場合は §US-6 のフローに従う。

### US-6: トークン失効を自動検知する

開発者として、token を外部で revoke した・期限が切れたといった場合に、アプリ側で自動的にログアウトされ、再ログイン導線が出るようにしたい。

- AC-6.1 任意の認証付き GitHub API リクエスト（`Authorization: Bearer <token>` 付き）が **HTTP 401** を返したとき、トークンを即座に Keychain から削除し、認証状態を未ログインに更新する。
- AC-6.2 401 検知が起きたあと、ユーザーが次に Settings 画面を開いたとき、プロフィール表示は消え「GitHub にログイン」ボタンが再表示されている。401 が起きた画面（例: 検索結果画面など）には **ユーザー向けのセッション切れ通知を出さない**。各画面は通常のエラー表示（401 由来の場合は「通信に失敗しました」相当の error-network 表示）に従う。次回 API 呼び出し時には未ログインとして扱われる。
- AC-6.3 アプリ起動時の `GET /user` で 401 が返った場合は、未ログイン状態として Settings 画面のログインボタンを表示する。ユーザー向けエラーは表示しない（起動時の体験を阻害しないため）。
- AC-6.4 401 以外の認証付きエラー（403 含む rate-limited、5xx、ネットワーク失敗）はログアウトを発生させない。**rate-limited は既存の rate-limited 表示に従う**（`repository-search.md` §4.3.2 を参照）。

### US-7: Device Flow の異常系を扱う

ログイン操作中の開発者として、認可が中断された場合や時間切れになった場合の挙動が予測可能であってほしい。

- AC-7.1 ユーザーが外部ブラウザで認可をキャンセル（polling 応答が `access_denied`）した時点で、コード表示画面は **「認可がキャンセルされました」相当のエラー表示 + 「閉じる」ボタン** を表示する。「閉じる」で Settings 画面に戻り、未ログインのまま維持される。
- AC-7.2 device code の有効期限（15 分）が切れて polling 応答が `expired_token` を返した時点で、コード表示画面は **「コードの有効期限が切れました」相当のエラー表示 + 「再開」/「閉じる」ボタン** を表示する。「再開」で新しい device code 取得から再開する。「閉じる」で Settings 画面に戻る。
- AC-7.3 polling 応答が `slow_down` を返した時点で、現在のポーリング間隔に **+5 秒** して継続する。ユーザー向けの表示は変化させない。
- AC-7.4 polling 中にネットワーク失敗（オフライン / タイムアウト / 5xx）が発生した場合、polling は継続する（同じ間隔で次のリクエストを試行する）。ユーザー向けエラー表示は出さない。

## 4. 振る舞い仕様

### 4.1 入出力一覧

| ユーザー操作 / 入力 | 前提条件 | システム応答 / 表示 |
|---|---|---|
| Settings 画面初回表示 | 未ログイン | 「GitHub にログイン」ボタンを表示。プロフィール非表示。レート制限は値があれば表示 |
| Settings 画面初回表示 | ログイン済み | プロフィール（avatar / login / name）と「ログアウト」ボタンを表示 |
| 「GitHub にログイン」をタップ | 未ログイン | コード表示画面に遷移、device code 取得 API を 1 回発火、loading 表示 |
| device code 取得成功 | コード表示画面 loading 中 | ユーザーコード（`XXXX-XXXX`）と認可 URL を表示、polling 開始、3 操作（ブラウザで開く / コピー / キャンセル）が有効化 |
| device code 取得失敗（network / 5xx） | コード表示画面 loading 中 | エラー表示 + 「再試行」/「閉じる」ボタン。再試行で device code 取得を再発火、閉じるで Settings 画面に戻る |
| 「ブラウザで開く」をタップ | コード表示画面 | 認可 URL を外部 Safari で開く、アプリは画面遷移せず polling を継続 |
| 「コードをコピー」をタップ | コード表示画面 | ユーザーコードをクリップボードにコピー、画面遷移なし |
| polling 応答 `authorization_pending` | polling 中 | 次のポーリングまで現状維持 |
| polling 応答 `slow_down` | polling 中 | ポーリング間隔に +5 秒、画面表示は変化なし |
| polling 応答 `access_denied` | polling 中 | polling 停止、「認可がキャンセルされました」エラー表示 + 「閉じる」ボタン |
| polling 応答 `expired_token` | polling 中 | polling 停止、「コードの有効期限が切れました」エラー表示 + 「再開」/「閉じる」ボタン |
| polling 応答 access_token 取得成功 | polling 中 | token を Keychain に保存、`GET /user` 発火 → プロフィール取得・保存、認証状態をログイン済みに更新、コード表示画面を閉じ Settings 画面に戻る |
| polling 中にネットワーク失敗 | polling 中 | polling を継続（次の間隔で再試行）、ユーザー向けエラー表示なし |
| 「キャンセル」をタップ | コード表示画面 | polling 停止、Settings 画面に戻る、未ログイン維持 |
| Settings 画面で「ログアウト」をタップ | ログイン済み | 確認ダイアログ表示 |
| 確認ダイアログで「ログアウト」をタップ | ログイン済み | Keychain から token 削除、認証状態を未ログインに更新、プロフィール表示クリア、ログインボタン再表示。レート制限値は「未取得」に戻す |
| 確認ダイアログで「キャンセル」をタップ | ログイン済み | ダイアログを閉じる、状態変化なし |
| 任意の認証付きリクエストで 401 を受信 | ログイン済み | Keychain から token 削除、認証状態を未ログインに更新。当該画面は通常のネットワークエラー表示に従う（セッション切れ専用文言は出さない） |
| アプリ起動時 `GET /user` で 401 | 起動直後 | Keychain クリア、未ログイン状態で Settings 画面表示、ユーザー向けエラー表示なし |
| 起動時 `GET /user` でネットワーク失敗 | 起動直後 | Keychain と保存済みプロフィールでログイン状態維持、プロフィール領域はキャッシュ表示 |
| 任意の GitHub API レスポンス受信 | 成否問わず | レスポンスヘッダから `X-RateLimit-Limit` / `X-RateLimit-Remaining` を抽出、保持し Settings 画面のレート制限セクションを更新 |

### 4.2 状態と表示

#### 4.2.1 認証状態（アプリ全体）

| 状態 | ユーザーから見える表示 | 主な遷移先 |
|---|---|---|
| **signedOut** | Settings に「ログイン」ボタン、プロフィール非表示 | ログインタップ → signingIn |
| **signingIn** | コード表示画面が前面に出ている。Settings タブ自体は signedOut の表示のままだが、ユーザーはコード表示画面と対話中 | 成功 → signedIn、`access_denied` / `expired_token` / 「キャンセル」 → signedOut |
| **signedIn** | Settings にプロフィール + ログアウトボタン | 「ログアウト」確定 → signedOut、401 検知 → signedOut |

#### 4.2.2 Settings 画面のプロフィール表示状態

ログイン状態と、起動直後の `GET /user` の進行状況に応じて、プロフィール領域は以下の状態を取る。

| 状態 | ユーザーから見える表示 | 主な遷移先 |
|---|---|---|
| **profile-hidden** | プロフィール領域そのものを表示しない | signedOut のとき常時この状態 |
| **profile-loading** | placeholder（avatar 形状 + 灰色テキスト相当）。プロフィールの値は表示しない | signedIn 直後 / 起動直後で `GET /user` 進行中 |
| **profile-loaded** | avatar 画像 + `login` + `name`（null 時は省略） | 通常状態 |
| **profile-cached** | 保存済みプロフィール（avatar / login / name）を表示。「最新の取得に失敗しました」相当の控えめな補足を併記 | signedIn 状態で起動直後 `GET /user` がネットワーク失敗したとき |

profile-loaded と profile-cached の表示内容は同じだが、補足文言の有無で区別する。401 で signedOut に切り替わった場合は profile-hidden に戻る。

#### 4.2.3 コード表示画面の状態

| 状態 | ユーザーから見える表示 | 主な遷移先 |
|---|---|---|
| **loading-device-code** | 中央にプログレスインジケータ、操作要素なし | 成功 → polling、失敗 → error-device-code |
| **error-device-code** | エラーメッセージ + 「再試行」「閉じる」 | 再試行 → loading-device-code、閉じる → Settings へ戻る |
| **polling** | ユーザーコード（`XXXX-XXXX`） + 認可 URL + 3 操作（ブラウザで開く / コピー / キャンセル） + 「認可を待っています…」進行表示 | 認可成功 → 自動クローズ、`access_denied` → error-access-denied、`expired_token` → error-expired、キャンセル → Settings へ戻る |
| **error-access-denied** | 「認可がキャンセルされました」 + 「閉じる」 | 閉じる → Settings へ戻る |
| **error-expired** | 「コードの有効期限が切れました」 + 「再開」「閉じる」 | 再開 → loading-device-code、閉じる → Settings へ戻る |

### 4.3 バリデーションと異常系

#### 4.3.1 入力バリデーション

- 本機能にはユーザーのテキスト入力フォームは存在しない。バリデーション対象は外部入力（GitHub API レスポンス、Keychain 読み出し値、Info.plist の Client ID）のみ。
- Client ID が空 / 取得失敗の場合は、Settings 画面の「ログイン」ボタンは表示するがタップで遷移したコード表示画面で **設定不備エラー** を表示する（後述 §4.3.2）。

#### 4.3.2 異常系の分類と挙動

| 分類 | 該当条件 | 挙動 |
|---|---|---|
| **device-code-network** | device code 取得時の URLError / 5xx | error-device-code 表示。再試行ボタンで再発火 |
| **device-code-config** | Client ID が空 / 設定不備 | error-device-code 表示。メッセージを「アプリの設定に問題があります」相当にし、再試行は機能上意味がないため「閉じる」のみ提示 |
| **access-denied** | polling 応答 `access_denied` | error-access-denied 表示 |
| **expired-token** | polling 応答 `expired_token` | error-expired 表示 |
| **slow-down** | polling 応答 `slow_down` | ポーリング間隔 +5 秒、UI 変化なし |
| **authorization-pending** | polling 応答 `authorization_pending` | 次のポーリングまで現状維持 |
| **polling-network** | polling 中の URLError / 5xx | polling 継続、UI 変化なし |
| **session-expired** | 認証付きリクエストの HTTP 401 | Keychain クリア・状態を signedOut に更新。発生元画面は通常のネットワークエラー表示に従い、本機能側で専用画面を出さない（Settings 画面では次回表示時にログインボタンが再出現する） |
| **rate-limited** | 認証付きリクエストの HTTP 403 + `X-RateLimit-Remaining: 0` または HTTP 429 | 各画面の既存 rate-limited 表示に従う。ログアウト処理は発生させない |
| **cancel** | ユーザーが「キャンセル」操作、または `CancellationError` | polling を停止し画面を閉じる。エラー表示は行わない |

#### 4.3.3 Device Flow 進行中の中断要因

以下のいずれかが発生したとき、polling は協調的にキャンセルされる。

- ユーザーが「キャンセル」をタップ
- ユーザーがコード表示画面から戻る操作（ナビゲーション pop / アプリ終了）
- `access_denied` / `expired_token` を受信
- access_token 取得成功

中断は **エラー表示として扱わない**。表示は §4.2.3 の状態遷移に従う。

## 5. URL / API 仕様

### 5.1 利用エンドポイント

| 目的 | メソッド | URL | 認証 |
|---|---|---|---|
| device code 取得 | POST | `https://github.com/login/device/code` | 不要 |
| ユーザー認可画面（外部 Safari で開く） | GET | `https://github.com/login/device` | ブラウザのセッション |
| access token 取得（polling） | POST | `https://github.com/login/oauth/access_token` | 不要 |
| プロフィール取得 | GET | `https://api.github.com/user` | Bearer |

注意:

- device code / access token のエンドポイントは `github.com` 配下であり、`api.github.com` ではない。既存の `ApiHost.github` の baseURL (`https://api.github.com`) とは別ホストとして扱う。
- リクエスト / レスポンスはいずれも `Accept: application/json` を付与し、JSON で扱う（既定では form-encoded だが、JSON も受け付ける）。

### 5.2 device code リクエスト / レスポンス

リクエストパラメータ（form-encoded または JSON）:

- `client_id`: Info.plist 由来の文字列
- `scope`: 半角スペース区切り（§7.2 で固定）

レスポンスフィールド（使用する分）:

- `device_code`（文字列）: polling で使う
- `user_code`（文字列）: UI 表示用
- `verification_uri`（URL）: UI 表示用（実体は `https://github.com/login/device` 固定）
- `expires_in`（秒）: device code 有効期限（GitHub 仕様で約 900 秒）
- `interval`（秒）: 初期 polling 間隔（既定 5 秒）

### 5.3 access token リクエスト / レスポンス（polling）

リクエストパラメータ:

- `client_id`: Info.plist 由来
- `device_code`: §5.2 で取得したもの
- `grant_type`: `urn:ietf:params:oauth:grant-type:device_code` 固定

レスポンスは以下の 2 系統:

| 種類 | 主なフィールド |
|---|---|
| 成功 | `access_token`、`token_type`（`bearer`）、`scope` |
| 進行中 / エラー | `error`（`authorization_pending` / `slow_down` / `expired_token` / `access_denied` 等）、`error_description`、`error_uri` |

注意:

- 成功レスポンスは HTTP 200。「進行中 / エラー」も HTTP 200 で `error` フィールドを含む形で返るのが GitHub の仕様。**HTTP ステータスだけで判定しない**。
- `error` フィールドが存在する場合の挙動は §4.3.2 に従う。

### 5.4 認証ヘッダ仕様

`api.github.com` を host とするすべての HTTP リクエストに対し、認証状態が signedIn のとき以下のヘッダを付与する。

```
Authorization: Bearer <access_token>
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
```

`X-GitHub-Api-Version` は GitHub 推奨。`Accept` はすでに既定ヘッダで設定済みのため重ねて指定してよい。signedOut のとき `Authorization` は付与しない。

`github.com`（OAuth 用ホスト）に対しては Bearer ヘッダを付与しない。

### 5.5 401 を検出する条件

- 認証付きリクエスト（`Authorization: Bearer` 付き）で HTTP 401 を受信したとき。
- ネットワーク層 / HTTP ステータスでの 401 検出に限定する。レスポンス body の文字列マッチは行わない。

## 6. 画面構成

### 6.1 画面一覧

| 画面 | 目的 |
|---|---|
| **Settings 画面**（既存改修） | ログインボタン / ログアウトボタン / プロフィール表示 / レート制限表示 |
| **コード表示画面**（新規） | Device Flow 進行中のユーザーコード・認可 URL・操作要素を提示 |

### 6.2 画面ごとの構成

#### Settings 画面（改修）

- **目的**: 認証状態の確認と操作、レート制限の可視化。プロフィール表示によりログイン成否をユーザーが目視確認できる。
- **配置要素**:
  - 認証セクション
    - 未ログイン時: 「GitHub にログイン」ボタン
    - ログイン時: avatar / `login` / `name`（null なら省略）と「ログアウト」ボタン
  - レート制限セクション
    - 「上限 / 残り」（取得済みの値、または「未取得」）
- **主要操作**: ログイン開始 / ログアウト確認
- **状態ごとの見え方**: §4.2.1 / §4.2.2 に従う

#### コード表示画面（新規）

- **目的**: Device Flow 進行中のユーザー入力支援とフィードバック
- **配置要素**:
  - 上部: 説明文（「下記コードをブラウザで入力してください」相当）
  - 中央: ユーザーコード（`XXXX-XXXX` 形式の大きめ表示）、認可 URL（タップ不可のテキスト）
  - 操作: 「ブラウザで開く」「コードをコピー」「キャンセル」
  - 進行表示: 「認可を待っています…」相当のテキストと、polling 中であることを示すインジケータ
  - 状態切替時のエラー文言領域（§4.2.3 の error-* 状態で使用）
- **主要操作**: ブラウザで認可 URL を開く / ユーザーコードをコピー / Device Flow をキャンセル / エラー時に「再試行」「再開」「閉じる」
- **状態ごとの見え方**: §4.2.3 に従う

## 7. データ要件

### 7.1 外部データソース

§5.1 のエンドポイントを参照。

### 7.2 要求 scope

Device Flow の `scope` パラメータには以下を固定で渡す:

- `read:user`: `GET /user` のプロフィール情報取得用

`repo` などの広範な権限スコープは本フェーズでは要求しない（認証必須機能は §2.2 で対象外のため）。将来的に「自分のリポジトリ一覧」等を追加する際に scope を拡張する。

### 7.3 永続データ

| 項目 | 保存先 | 保存内容 | 更新タイミング |
|---|---|---|---|
| access token | **Keychain** | `access_token` の文字列 | ログイン成功時に保存、ログアウト・401 検知・`access_denied` / `expired_token` 受信時に削除 |
| プロフィールキャッシュ | UserDefaults | `login` / `name` / `avatar_url` のみ | `GET /user` 成功時に上書き、ログアウト時に削除 |
| Client ID | Info.plist（`.xcconfig` 経由） | 文字列 | ビルド時に注入、実行時の更新なし |

注意:

- access token は **Keychain 必須**。UserDefaults / ファイル平文保存は不可。
- Keychain のアクセシビリティは `kSecAttrAccessibleAfterFirstUnlock` 相当（バックグラウンド復帰でも参照可能、デバイスロック中の起動でも参照可能）とする。生体認証付きの厳格な保護は §2.2 で対象外。
- プロフィールキャッシュは「起動直後の API 失敗時にも表示を維持する」ためだけに使う。レート制限値はキャッシュしない（ログイン状態が変わると意味が変わるため）。

### 7.4 必要なフィールド（受信レスポンス）

- `GET /user`: `login`, `id`, `avatar_url`, `name`

### 7.5 Client ID の配置仕様

- リポジトリには `Config.xcconfig.template`（追跡対象）と `.gitignore` に追加した `Config.xcconfig`（実体、追跡対象外）を置く。
- ビルド設定で `Config.xcconfig` を読み込み、Info.plist に `GitHubOAuthClientID` キーで注入する。
- 実行時は `Bundle.main.object(forInfoDictionaryKey: "GitHubOAuthClientID")` で取得する。空文字 / nil の場合は §4.3.2 の `device-code-config` 分類として扱う。

## 8. 非機能要件

### 8.1 性能

- device code 取得 API の応答到達から UI 反映（コードと URL の表示）までは **300ms 以内**。
- access token 取得成功からコード表示画面が閉じ Settings 画面に戻るまでは **500ms 以内**（`GET /user` の応答待ちは含めない。プロフィール表示は後追いで更新してよい）。
- polling は GitHub 仕様の `interval` を厳守し、`slow_down` 受信時のみ +5 秒する。クライアント側の追加 backoff は行わない。

### 8.2 アクセシビリティ

- ユーザーコード表示は **VoiceOver で読み上げ可能** とし、ハイフン区切りを意識した自然な読み上げになるようアクセシビリティラベルを別途設定する（例: `"Q E G N - W S X T"` の英数字逐次読みに近い形）。
- 「ブラウザで開く」「コードをコピー」「キャンセル」「ログイン」「ログアウト」「再試行」「再開」「閉じる」の各ボタンに **アクセシビリティラベル** を付与する。
- 認証状態（signedIn / signedOut）の変化を VoiceOver 利用者にアナウンスする `accessibilityAnnouncement` の発火は本フェーズでは要求しない。

### 8.3 セキュリティ

- access token を UserDefaults / ファイル平文 / メモリの長期保持 / ログ出力 のいずれにも残さない。`print` / `os_log` でトークン文字列を含めない。
- 401 受信時は Keychain から削除する。アプリ終了時に削除する必要はない。
- Keychain アクセシビリティは §7.3 に従い、生体認証は要求しない。
- Client ID は Info.plist に同梱されるため、本仕様では「秘匿情報」として扱わない。`.xcconfig` 経由でリポジトリ共有を避ける目的は **誤って公開リポジトリで利用される事故防止** にあり、ビルド成果物に含まれる事自体は許容する。

### 8.4 信頼性

- Device Flow の polling・ログイン / ログアウト処理が strict concurrency 違反を起こさない。
- ログイン状態の変化（signedOut → signedIn → signedOut）を任意の回数繰り返してもメモリリーク・Task 漏れ・stale な polling が残らない。
- 401 検知のフックは認証層に一元化し、各画面の Repository / Observable Model に重複実装させない。

### 8.5 ローカライズ

- 本フェーズは UI 文言を日本語単一とする。多言語化は将来課題（§10）。

## 9. 完了の定義

以下のすべてを満たしたとき、本機能は完了とみなす。

- §3 のすべての受け入れ条件（AC-1.1〜AC-7.4）が満たされる。
- §4.3 の異常系分類すべてに対し、定義された表示と回復手段が機能する。
- §5 の各 API 呼び出しが、認証ヘッダの有無・エンドポイントの host 切り分けを含めて仕様通りに動作する。
- §7 の永続データ（Keychain / UserDefaults / Info.plist）が仕様通りに扱われる。
- §10 の検証要件のテストが Swift Testing ですべて通る。
- §8 の非機能目標を満たす（性能 / VoiceOver ラベル / セキュリティ / strict concurrency 警告無し）。

## 10. 検証要件と AC の対応

§3 の各受け入れ条件に対し、Swift Testing で検証すべき観点を定義する。具体的なテスト設計・Mock 構造には踏み込まない。

| 検証観点 | 対応 AC |
|---|---|
| 未ログイン時の Settings 画面に「ログイン」ボタンが表示される | AC-1.1, AC-4.2 |
| 「GitHub にログイン」タップでコード表示画面に遷移し、device code 取得 API が 1 回発火する | AC-1.1, AC-1.2 |
| device code 取得成功で ユーザーコード（`XXXX-XXXX` 形式）と認可 URL が表示され、3 操作が有効化される | AC-1.3 |
| 「ブラウザで開く」で外部 Safari に認可 URL を渡す | AC-1.4 |
| 「コードをコピー」でユーザーコードがクリップボードに入る | AC-1.5 |
| polling 間隔がレスポンス `interval` を初期値とし、`slow_down` 受信で +5 秒される | AC-1.6, AC-7.3 |
| polling 応答 access_token 成功で token が Keychain に保存され、コード表示画面が閉じる | AC-1.7 |
| ログイン直後に `GET /user` が発火し、プロフィール（avatar / login / name）が Settings 画面に表示される。`name` null は省略される | AC-1.8 |
| 「キャンセル」で polling 停止・Settings に戻る・未ログイン維持 | AC-1.9 |
| 認証状態が signedIn のとき `api.github.com` への全リクエストに `Authorization: Bearer` が付与される | AC-2.1 |
| 認証状態が signedOut のとき `Authorization` ヘッダは付与されない | AC-2.2 |
| ログイン / ログアウトの切替は次回以降のリクエストから反映される（進行中の API は影響を受けない） | AC-2.3 |
| Settings の「レート制限」セクションが直近 API レスポンスから `X-RateLimit-Limit` / `X-RateLimit-Remaining` を抽出して表示する | AC-3.1, AC-3.2 |
| ログイン / ログアウトの瞬間にレート制限表示が「未取得」にリセットされる | AC-3.4 |
| 「ログアウト」タップで確認ダイアログが出る | AC-4.1 |
| 確認ダイアログで「ログアウト」確定 → Keychain クリア・signedOut へ更新・プロフィールクリア・ログインボタン再表示 | AC-4.2 |
| 確認ダイアログで「キャンセル」 → 状態変化なし | AC-4.3 |
| アプリ起動時に Keychain から token を読み出して signedIn を復元する | AC-5.1 |
| 起動直後の `GET /user` 失敗（ネットワーク）でも Keychain と保存済みプロフィールで signedIn を維持し、プロフィールはキャッシュ表示する | AC-5.2 |
| 起動直後の `GET /user` で 401 を受けたとき、Keychain クリア・signedOut へ更新するがユーザー向けエラー表示は出さない | AC-5.3, AC-6.3 |
| 認証付きリクエストで 401 を受けたとき、Keychain クリア・signedOut へ更新する。発生元画面は通常のネットワークエラー表示のままで、専用のセッション切れ文言は出さない | AC-6.1, AC-6.2 |
| rate-limited / 5xx / ネットワーク失敗ではログアウトしない | AC-6.4 |
| polling 応答 `access_denied` で error-access-denied 表示、「閉じる」で Settings に戻る | AC-7.1 |
| polling 応答 `expired_token` で error-expired 表示、「再開」で device code 取得を再発火、「閉じる」で Settings に戻る | AC-7.2 |
| polling 中のネットワーク失敗で polling は継続し、ユーザー向けエラーは出さない | AC-7.4 |
| `device-code-config`（Client ID 空）分類で「閉じる」のみ提示される | §4.3.2 |
| 認証状態の変化（signedOut → signedIn → signedOut）を任意回繰り返しても Task 漏れ・stale polling が残らない | §8.4 |
| Keychain 操作（save / load / delete）が strict concurrency 違反を起こさない | §8.4 |
| ユーザーコードが VoiceOver で文字単位に近い形で読み上げられる | §8.2 |

## 11. 将来課題

§2.2 の対象外項目のうち、優先度の高いものから列挙する。

1. **認証必須機能の追加**: 「自分のリポジトリ一覧」「自分の Issue / PR 一覧」「starred リポジトリ」「following 一覧」など。これらに合わせて scope を `repo` / `public_repo` などに拡張する。
2. **GitHub App** ベースの認証（fine-grained permissions、`installation_id` 切替などの学習対象）
3. **PKCE 付き Web Application Flow** / `ASWebAuthenticationSession` ベースの redirect 認証フロー
4. **Personal Access Token (PAT) の手入力** 経路の追加（学習比較対象として）
5. **複数アカウントの同時保持・切替**
6. **scope の動的選択 UI**（`public_repo` のみで開始 → 後から `repo` を要求するなど）
7. **`X-RateLimit-Reset` を用いたカウントダウン表示**
8. **生体認証 / アプリパスコードによる Keychain アクセス保護**（`SecAccessControl` 利用）
9. **ログイン / ログアウト時の既存画面の自動再フェッチ**（in-flight request の無効化 + 自動再実行）
10. **401 発生元画面でのセッション切れ専用通知**（現状は通常のエラー表示に倒している）
11. **多言語対応 (i18n)**

## 12. 参照

- `github-client-swiftui/docs/requirements.md`（全体要求定義。§2.2 を本書で更新）
- `github-client-swiftui/docs/requirements/repository-search.md`（rate-limited / cancel の表記揃え）
- `github-client-swiftui/docs/requirements/deeplink.md`（`AppCoordinator` 経由のタブ・path 操作の前例として）
- `github-client-swiftui/CLAUDE.md`（プロジェクト前提・実装規約）
- `github-client-swiftui/.claude/rules/swift-coding.md`（Swift / SwiftUI 実装ルール）
- 関連既存実装（参照のみ。設計指示はしない）
  - `github-client-swiftui/Common/Networking/HttpClient.swift`
  - `github-client-swiftui/Common/Networking/URLSessionHttpClient.swift`
  - `github-client-swiftui/Common/Storage/UserDefaultsStorage.swift`
  - `github-client-swiftui/Common/Navigation/AppCoordinator.swift`
  - `github-client-swiftui/Common/Navigation/AppRoute.swift`
  - `github-client-swiftui/Features/Settings/SettingsView.swift`
  - `github-client-swiftui/RootView.swift`
- GitHub Docs: Authorizing OAuth apps — https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
- GitHub Docs: Get the authenticated user — https://docs.github.com/en/rest/users/users#get-the-authenticated-user
- GitHub Docs: Rate limits — https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- Apple Developer: Keychain Services — https://developer.apple.com/documentation/security/keychain_services
