# Phase enum 定義の一貫性統一

## ステータス: 未着手

## 概要

各 Model の Phase enum の定義スタイルが混在している。統一することでコードの可読性と予測可能性を向上させる。

## 現状の不一致

| Model | Phase の定義場所 | 名前 |
|---|---|---|
| `RepositorySearchModel` | トップレベル `enum RepositorySearchPhase` | `RepositorySearchPhase` |
| `RepositoryDetailModel` | nested `enum Phase` | `RepositoryDetailModel.Phase` |
| `IssueListModel` | トップレベル `enum IssueListPhase` | `IssueListPhase` |
| `IssueDetailModel` | nested `enum Phase` / `enum CommentsPhase` | `IssueDetailModel.Phase` |
| `DeviceFlowModel` | トップレベル `enum DeviceFlowPhase` | `DeviceFlowPhase` |
| `SettingsModel` | トップレベル `enum SettingsProfileState` | `SettingsProfileState` |

### 不一致ポイント

1. **定義場所**: トップレベル vs nested type
2. **命名**: `Phase` vs `State` (SettingsModel のみ `State`)
3. **Sendable / Equatable 準拠**: 一部は付いていて一部は付いていない
   - `RepositorySearchPhase: Sendable, Equatable` ✓
   - `RepositoryDetailModel.Phase` — Sendable も Equatable もなし ✗

## 改善案

1. 全て nested type (`Model.Phase`) に統一する — 名前空間がクリーンで、同じファイル内で完結する
2. 全ての Phase に `Sendable, Equatable` を付与する — テストでの比較、actor 境界越えに有用
3. 名前は `Phase` に統一する（`State` は SwiftUI の `@State` と紛らわしい）

## 影響範囲

- 各 Feature の Model ファイル
- 各 Feature の View ファイル（型名の参照）
- 関連テスト
