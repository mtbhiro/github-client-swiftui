# ディープリンク動作確認ガイド

## URL スキーム

- スキーム: `githubclient`
- ホスト: `repo`

## 対応ディープリンク一覧

| URL | 遷移先 |
|---|---|
| `githubclient://repo/{owner}/{name}` | リポジトリ詳細画面 |
| `githubclient://repo/{owner}/{name}/issues` | Issue 一覧画面（リポジトリ詳細を経由するスタック） |

## シミュレータでの動作確認

シミュレータでアプリを起動した状態で、ターミナルから `xcrun simctl openurl` を実行する。

### リポジトリ詳細画面

```bash
xcrun simctl openurl booted "githubclient://repo/apple/swift"
```

確認ポイント:
- Search タブに自動切替される
- apple/swift のリポジトリ詳細画面が表示される

### Issue 一覧画面

```bash
xcrun simctl openurl booted "githubclient://repo/apple/swift/issues"
```

確認ポイント:
- Search タブに自動切替される
- ナビゲーションスタックに「リポジトリ詳細 → Issue 一覧」の 2 画面が積まれる
- 戻るボタンでリポジトリ詳細画面に戻れる

## 異常系の確認（無視されることを確認）

以下はすべて無視される（画面遷移が起きない）ことを確認する。

```bash
# スキーム違い
xcrun simctl openurl booted "https://repo/apple/swift"

# ホスト違い
xcrun simctl openurl booted "githubclient://user/apple"

# パスセグメント不足
xcrun simctl openurl booted "githubclient://repo/apple"

# 未対応のサブパス
xcrun simctl openurl booted "githubclient://repo/apple/swift/pulls"

# 末尾スラッシュ
xcrun simctl openurl booted "githubclient://repo/apple/swift/"

# クエリ付き
xcrun simctl openurl booted "githubclient://repo/apple/swift?ref=main"
```

## 補足

- スキームとホストは case-insensitive（`GithubClient://REPO/apple/swift` も有効）
- Issue 一覧の `issues` セグメントは case-sensitive（`Issues` は無効）
- 複数のシミュレータが起動している場合は `booted` の代わりにデバイス UDID を指定する
