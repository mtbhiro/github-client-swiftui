# エラー表示 View の再利用化

## ステータス: 未着手

## 概要

エラー状態の表示が各画面で個別に実装されている。アイコン + メッセージ + 再試行ボタンのパターンは共通なのに、View の構造・スタイルが微妙に異なる。共通コンポーネントに集約すべき。

## 該当箇所

- `RepositorySearchView.swift:266-297` — `errorNetworkView`, `errorRateLimitedView`
- `RepositoryDetailView.swift:195-211` — `errorView(message:)`
- `IssueListView.swift` — 同様のエラー表示
- `IssueDetailView.swift` — 同様のエラー表示

## 改善案

汎用的なエラー表示コンポーネントを作成する。`Common/Component/` に既に `ErrorStateView` が存在するなら、それを全画面で統一利用する。存在しないなら新規作成する。

```swift
struct ErrorStateView: View {
    let icon: String
    let message: String
    let detail: String?
    let retryAction: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let retryAction {
                Button("再試行", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

## 影響範囲

- `Common/Component/` に共通 View 追加（または既存を拡張）
- 各 Feature の View ファイル（個別実装を共通コンポーネント呼び出しに置換）
