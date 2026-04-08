---
name: release
description: local-runner の新バージョンをリリースする。VERSION更新・ビルド・GitHub Release作成・Homebrew Formula更新を一括で行う。「リリースして」「バージョン出して」「次のバージョン」などと言ったときに使う。
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion
argument-hint: "[バージョン番号 (省略時は自動判定)]"
---

# リリース手順

local-runner の新バージョンをリリースする。
現在の remote main をベースにビルド・リリースを行う。

## 前提

- 作業ディレクトリ: `/Users/shingo/projects/github.com/gehnmaisoda/local-runner`
- Homebrew tap: `/Users/shingo/projects/github.com/gehnmaisoda/homebrew-local-runner`
- main ブランチで作業すること

## Step 1: 状況確認

1. main ブランチにいること、ワーキングツリーがクリーンであることを確認
2. `git pull` で最新を取得
3. 現在の VERSION ファイルを読む
4. 前回リリース以降のコミットを確認: `git log v<現在バージョン>..HEAD --oneline`

## Step 2: バージョン決定

引数でバージョンが指定されていればそれを使う。

指定がない場合は、前回リリース以降のコミット内容から判定する:
- **patch** (0.x.Y): バグ修正、軽微な変更のみ
- **minor** (0.X.0): 新機能の追加
- **major** (X.0.0): 破壊的変更

判断に迷う場合は AskUserQuestion でユーザーに相談する。

## Step 3: VERSION 更新・コミット・push

```bash
# VERSION ファイルを更新（Edit ツールで）
git add VERSION
git commit -m "chore: bump version to <新バージョン>"
git push
```

## Step 4: ビルド

```bash
make clean && make dist
```

成功すると `dist/local-runner-<バージョン>-arm64.tar.gz` が生成される。

## Step 5: GitHub Release 作成

前回リリース以降のコミットからリリースノートを作成する。

カテゴリ分類:
- `fix:` → **Bug Fixes**
- `feat:` → **New Features**
- `refactor:` / `chore:` / `docs:` → **Other Changes**（軽微なら省略可）

```bash
gh release create v<バージョン> dist/local-runner-<バージョン>-arm64.tar.gz \
  --title "v<バージョン>" \
  --notes "<リリースノート>"
```

リリースノートの末尾には必ず以下を含める:

```markdown
## Update
\`\`\`bash
brew upgrade local-runner
lr install
\`\`\`
```

## Step 6: Homebrew Formula 更新

```bash
# sha256 取得
shasum -a 256 dist/local-runner-<バージョン>-arm64.tar.gz
```

`/Users/shingo/projects/github.com/gehnmaisoda/homebrew-local-runner/Formula/local-runner.rb` の url, sha256, version を更新する（Edit ツールで）。

```bash
cd /Users/shingo/projects/github.com/gehnmaisoda/homebrew-local-runner
git add Formula/local-runner.rb
git commit -m "chore: bump local-runner to <バージョン>"
git push
```

## Step 7: 完了報告

リリースした内容をユーザーに報告する:
- リリースURL
- 変更内容のサマリー
- `brew upgrade local-runner && lr install` でアップデート可能であること
