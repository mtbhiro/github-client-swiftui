# リファクタ・改善タスク一覧

> コードレビュー（2026-05-27）で洗い出した改善タスク。1 つずつ対応して完了したらステータスを更新する。

## 優先度: 高（コード品質・安全性）

| # | タスク | ファイル | ステータス |
|---|--------|----------|-----------|
| 1 | [DTO の force unwrap 除去](refactor-dto-force-unwrap.md) | DTO 各種 | 完了 |
| 2 | [suppressQueryDidSet フラグ除去](refactor-suppress-query-didset.md) | RepositorySearchModel | 完了 |
| 3 | [Environment デフォルト値の Mock 排除](refactor-environment-default-mock.md) | GithubRepoRepository | 完了 |
| 4 | [ネットワークタイムアウトの設定](refactor-network-timeout.md) | URLSessionHttpClient | 完了 |

## 優先度: 中（設計の一貫性・DRY）

| # | タスク | ファイル | ステータス |
|---|--------|----------|-----------|
| 5 | [SearchRoute / BookmarksRoute の重複解消](refactor-route-duplication.md) | AppRoute, AppCoordinator | 完了 |
| 6 | [navigationDestination ルーティングの抽出](refactor-navigation-destination-extract.md) | RepositorySearchView, BookmarkListView | 完了 |
| 7 | [HTTP ヘッダの case-insensitive 処理統一](refactor-header-case-insensitive.md) | URLSessionHttpClient, RateLimitObserver, ErrorMapper | 完了 |
| 8 | [Phase enum 定義の一貫性統一](refactor-phase-enum-consistency.md) | 各 Model | 完了 |
| 9 | [AsyncImage とカスタム ImageLoader の統一](refactor-async-image-unification.md) | RepositoryDetailView, SettingsView | 完了 |
| 10 | [エラー表示 View の再利用化](refactor-error-view-reusable.md) | 各 Feature View | 完了 |

## 優先度: 低（コード衛生・将来の保守性）

| # | タスク | ファイル | ステータス |
|---|--------|----------|-----------|
| 11 | [ページネーション定数の集約](refactor-per-page-constant.md) | RepositorySearchModel, IssueListModel, Repository | 完了 |
| 12 | [DateFormatter の集約](refactor-date-formatter-centralize.md) | DTO 各種, RepositorySearchView | 完了 |
| 13 | [ApiHost.defaultHeaders の重複解消](refactor-api-host-default-headers.md) | HttpClient | 完了 |
| 14 | [構造化ログの導入](refactor-add-logging.md) | プロジェクト全体 | 完了 |

## 依存関係

- **#6 → #5**: ルーティングテーブル抽出は Route 型の統一後に行うのが自然
- **#7**: ヘッダ正規化を入れると #8 の RateLimitObserver 側も簡潔になる
