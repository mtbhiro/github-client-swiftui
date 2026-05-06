---
name: commit-and-push
description: 現在の変更を 1 つのコミットにまとめて push する。コミットメッセージは Conventional Commits 風のプレフィックス + 日本語の体言止めサマリ + 概要の箇条書きで一貫性を保つ。「コミットしてプッシュ」「commit して push」など、ユーザーが現在の変更をコミット&プッシュしたい意図を示したときに使う。
---

# commit-and-push

現在の作業ツリーの変更を 1 つのコミットにまとめ、リモートに push するスキル。

## メッセージ規約(必ず従う)

```
<type>: <日本語の体言止めサマリ(50字以内目安)>

- 変更点1
- 変更点2
- 変更点3
```

### type は次の 5 つから 1 つだけ選ぶ

- `feat`: 新機能の追加
- `fix`: バグ修正
- `refactor`: 機能を変えない内部改善
- `docs`: ドキュメント・コメントのみの変更
- `chore`: 設定・依存・ビルド・雑務(.gitignore、CI、Xcode 設定 など)

迷ったときの判断基準:
- ユーザーから見える挙動が増えた → `feat`
- ユーザーから見える挙動の不具合を直した → `fix`
- 挙動は変えず構造だけ変えた → `refactor`
- ドキュメントだけ → `docs`
- それ以外で開発フローを支える変更 → `chore`

複数 type が混ざる変更は、原則 **最も主要な変更** の type を採用する(切り分けは行わない)。

### サマリ(1 行目)

- 日本語の体言止め(「〜を追加」「〜を修正」「〜に対応」など)
- 句点(。)は付けない
- 50 字以内を目安、最大でも 72 字
- スコープ表記(`feat(search): ...`)は使わない
- breaking change マーク(`!`)は使わない

### 本文(箇条書き)

- 1 行目との間に空行を 1 つ
- `- ` で始まる箇条書きで、変更点を「何を」中心に簡潔に列挙
- 変更点が 1 つだけのときは本文を省略してよい
- 「なぜ」を書く必要があるときだけ短く添える(冗長な背景説明は不要)

## 実行手順

1. **変更状況の把握**(以下を並列実行):
   - `git status`(`-uall` は使わない)
   - `git diff`
   - `git diff --staged`
   - `git log --oneline -10`(直近のスタイル参照)

2. **変更内容の分析とメッセージ起案**:
   - すべてのステージ済み + 未ステージの変更を読み、主要な変更を特定する
   - 上記規約に従って type とサマリを決める
   - 変更点を 2〜5 個程度の箇条書きにまとめる
   - `.env`、`*.credentials.json` 等のシークレット候補ファイルが含まれていないか確認する。含まれていればコミット前にユーザーに警告する

3. **ステージング → コミット → 確認**(以下を並列実行可):
   - 関連ファイルを個別に `git add <path>` で追加(`git add -A` / `git add .` は使わない)
   - HEREDOC でコミットメッセージを渡してコミット:
     ```bash
     git commit -m "$(cat <<'EOF'
     <type>: <サマリ>

     - 変更点1
     - 変更点2

     Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
     EOF
     )"
     ```
   - コミット後に `git status` で成功を確認

4. **push**:
   - `git push` を実行
   - 上流が未設定なら `git push -u origin <current-branch>` を使う
   - main / master への force push は絶対に行わない

5. **完了報告**:
   - 1〜2 文で「何をコミットして push したか」を報告(コミットハッシュの範囲を含める)

## 守ること

- pre-commit hook が失敗したら、原因を直して**新しいコミット**を作る(`--amend` は使わない)
- `--no-verify` / `--no-gpg-sign` 等の hook スキップは絶対に使わない
- amend は行わない(常に新規コミットを作る)
- `.claude/settings.local.json` や `.claude/worktrees/` は `.gitignore` 済みなので追加されないが、念のため `git status` の Untracked を見て紛れ込ませない

## 例

良い例:
```
feat: リポジトリ検索画面に debounce 付き検索を追加

- 入力 300ms の debounce で検索を発火
- idle / loading / loaded / error の状態表示を実装
- @Observable Model に Task キャンセルを集約
```

```
chore: .gitignore に Claude Code のローカル設定を追加

- .claude/settings.local.json を除外
- .claude/worktrees/ を除外
```

```
fix: 検索結果クリア時のフォーカスが外れる不具合を修正
```

悪い例(避ける):
- `feat(search): add debounce to repo search` ← スコープ + 英語(規約から外れる)
- `update files` ← type 無し、内容も曖昧
- `feat: 色々追加した。` ← 句点あり、内容が曖昧
- `feat!: ...` ← breaking マーク不使用
