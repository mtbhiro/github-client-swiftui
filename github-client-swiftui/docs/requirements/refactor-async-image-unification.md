# AsyncImage とカスタム ImageLoader の使い分け統一

## ステータス: 未着手

## 概要

アバター画像表示に 2 つの異なるアプローチが混在している。

1. **`AsyncImage`（Apple 標準）** — `RepositoryDetailView.swift:53`, `SettingsView.swift:136`
2. **カスタム `ImageLoader` プロトコル** — `AvatarImageView`（Common/Component）

`AsyncImage` は OS 管理のキャッシュを使い、`URLCache` ベースのキャッシュ制御ができない。テスト・Preview での画像差し替えもできない。一方 `AvatarImageView` は Protocol ベースの `ImageLoader` を使っており、テスタビリティが高い。

## 改善案

アバター画像の表示を `AvatarImageView` に統一する。`AsyncImage` は手軽だが、以下の理由でカスタムコンポーネントに寄せるのが望ましい:

1. **キャッシュ制御**: `URLCache` を使った HTTP キャッシュヘッダの尊重（PRD §3.5 の方針）
2. **テスタビリティ**: Preview / Test で Mock 画像を差し込める
3. **一貫性**: 画像表示のフォールバック処理が 1 箇所に集約される

## 影響範囲

- `Features/RepositoryDetail/RepositoryDetailView.swift` — `AsyncImage` → `AvatarImageView` に置換
- `Features/Settings/SettingsView.swift` — 同上
- `Features/Bookmark/BookmarkListView.swift` — 同上（使用されていれば）
