# XcodeBuildMCP / AXe の落とし穴

XcodeBuildMCP の UI 自動化系ツール（`snapshot_ui` / `tap` 等）は内部で AXe を使っており、AXe は iOS Simulator の Accessibility (AX) ツリーを読みに行く。つまり `snapshot_ui` で見える要素は概ね VoiceOver が認識するものと一致する。

## `snapshot_ui` で `Tab Bar` の children が空になる

### 症状

`TabView` を持つ画面で `snapshot_ui` を呼ぶと、タブバー領域は `AXGroup "Tab Bar"` として現れるが `children: []` になり、個別タブ（検索 / ブックマーク / 設定 など）が tree から取れない。

### 原因

iOS の `UITabBar` 配下の `UITabBarButton` は非公開クラスで、Apple の Accessibility API が children として返さない既知挙動。SwiftUI の `TabView` も最終的に UIKit の `UITabBar` にブリッジされるため、同じ制約を受ける。

**実装側の問題ではない。** 標準的な `TabView` + `Label("...", systemImage: ...)` + `.tag(...)` で十分正しい。実機の VoiceOver はタブを正常に読み上げる。

### 回避策

自動化（XcodeBuildMCP / AXe）からタブを叩きたいときは座標フォールバックを使う。

1. `snapshot_ui` で `Tab Bar` グループの `AXFrame` を取得
2. その内側の x 座標を計算（タブが 3 つなら横幅を 3 等分した中央 x）
3. `tap x: y:` で叩く

`.accessibilityIdentifier` を付けても改善しない可能性が高い（`UITabBar` 自体の制約のため）。識別子追加は VoiceOver には影響しないので試す価値はあるが、過度な期待はしない。

### 一次ソース

- [aliceisjustplaying/claude-resources-monorepo `skills/axe/SKILL.md`](https://github.com/aliceisjustplaying/claude-resources-monorepo/blob/main/skills/axe/SKILL.md) — AXe スキル定義に `Tab bar items often require coordinates instead of labels.` と明記
- [Issues with making UITabBar accessible (mokagio, 2015)](https://mokagio.github.io/tech-journal/2015/02/17/ios-uitabbar-accessibility.html) — `UITabBarItem` の accessibilityLabel が効かない歴史的経緯

---

## SourceKit が `AppCoordinator` 等を「Cannot find in scope」と誤検知する

### 症状

`RepositorySearchView.swift` などで、`@Environment(AppCoordinator.self)` や `SearchRoute`、`RepositoryDetailView` といったプロジェクト内の型に対して SourceKit が大量のエラー（`Cannot find 'X' in scope` / `Generic parameter 'T' could not be inferred`）を出す。

### 原因

エディタ側の SourceKit インデックス未解決による偽陽性。XcodeBuildMCP の `build_sim` / `build_run_sim` は実際には成功しており、コードに問題はない。

### 回避策

無視して問題ない。`mcp__XcodeBuildMCP__build_sim` を `extraArgs: ["build-for-testing"]` で走らせて成功するなら、SourceKit 側の表示は信用しない。

どうしても消したい場合は Xcode で Clean Build Folder → 再 build でインデックスが再生成される（XcodeBuildMCP セッションには直接影響しない）。

### 一次ソース

- セッション内での実観測のみ。一般化された一次ソースは無し
