---
name: lr
description: LocalRunner (lr) のタスク管理。ユーザーが「lrに登録して」「local runnerでスケジュールして」「ローカルランナーに追加」「定期実行したい」「タスクを作りたい」「ジョブを確認したい」「スケジュールを変更したい」「実行履歴を見たい」「設定を変えたい」などと言ったときに使う。
user-invocable: true
allowed-tools: Bash(lr *)
argument-hint: "[操作内容を自然言語で]"
---

# LocalRunner タスク管理

`lr` CLI を使ってローカルジョブランナーのタスクを管理する。

## 重要なルール

- **全コマンドに `--json` を付けること**。出力を正確にパースするために必須。
- 削除時は **`--yes`** を必ず付けて確認プロンプトをスキップする。
- コマンドの実行結果は JSON で返る。成功時は各コマンド固有の形式、エラー時は `{"success":false,"error":"..."}` 形式。
- ユーザーに結果を伝える際は JSON をそのまま見せず、**人間が読みやすい形に整形**して説明する。

## コマンド一覧

### タスクの参照

```bash
# 全タスク一覧
lr list --json

# タスク詳細（定義・状態・直近の実行結果）
lr show <タスクID> --json

# サマリー（件数・実行中・次回予定）
lr status --json
```

### タスクの作成

```bash
lr create \
  --name "<タスク名>" \
  --command "<実行コマンド>" \
  --schedule-type <タイプ> \
  [スケジュールオプション] \
  [その他オプション] \
  --json
```

**スケジュールタイプ:**

| タイプ | 追加オプション | 例 |
|--------|---------------|-----|
| `every_minute` | なし | そのまま毎分実行 |
| `hourly` | `--minute <0-59>` | `--minute 30` → 毎時30分 |
| `daily` | `--time "HH:mm"` | `--time "03:00"` → 毎日3時 |
| `weekly` | `--weekdays "1,3,5"` `--time "HH:mm"` | 1=月〜7=日 |
| `monthly` | `--month-days "1,15,-1"` `--time "HH:mm"` | -1=月末 |
| `cron` | `--cron "<式>"` | `--cron "*/5 * * * *"` |

**その他オプション:**
- `--id <id>` — タスクID（省略時は名前から自動生成）
- `--working-dir <path>` — 作業ディレクトリ
- `--timeout <秒>` — タイムアウト
- `--catch-up` / `--no-catch-up` — スリープ復帰時の実行（デフォルト: on）
- `--notify` / `--no-notify` — 失敗時 Slack 通知（デフォルト: off）
- `--disabled` — 無効状態で作成

### タスクの編集

指定したフィールドだけを更新する。未指定フィールドは現在値を維持。

```bash
lr edit <タスクID> --timeout 1200 --notify --json
lr edit <タスクID> --schedule-type weekly --weekdays "1,5" --time "02:00" --json
```

### タスクの削除

```bash
lr delete <タスクID> --yes --json
```

### タスクの実行・停止

```bash
# 即時実行（非同期、開始だけ確認）
lr run <タスクID> --json

# 実行して完了まで待機（結果も取得）
lr run <タスクID> --wait --json

# 実行中のタスクを停止
lr stop <タスクID> --json
```

### 有効/無効の切り替え

```bash
lr toggle <タスクID> --json
```

### 実行履歴

```bash
# 全タスクの履歴（デフォルト20件）
lr logs --json

# 特定タスクの履歴
lr logs <タスクID> --json

# 件数指定
lr logs <タスクID> -n 5 --json
```

### 設定

```bash
# 設定表示
lr config get --json

# 設定変更
lr config set default_timeout 1800 --json
lr config set slack_webhook_url "https://hooks.slack.com/..." --json
```

### その他

```bash
# タスク定義ファイルの再読み込み
lr reload --json

# セットアップ診断
lr doctor --json
```

## 終了コード

| コード | 意味 |
|--------|------|
| 0 | 成功 |
| 1 | 一般エラー |
| 2 | タスク/リソースが見つからない |
| 3 | デーモン未接続 |
| 4 | バリデーションエラー |

終了コードが 3 の場合はデーモンが起動していない可能性がある。ユーザーに `lr doctor` の実行を案内する。

## よくあるワークフロー

**ユーザー: 「毎日3時にバックアップしたい」**
1. `lr create --name "..." --command "..." --schedule-type daily --time "03:00" --json`
2. 作成結果をユーザーに報告

**ユーザー: 「失敗してるタスクある？」**
1. `lr list --json` で全タスクを取得
2. `lastRun.status` が `failure` や `timeout` のものを抽出
3. 該当があれば `lr logs <id> --json` で詳細を確認して報告

**ユーザー: 「このタスクを今すぐ実行して結果を見せて」**
1. `lr run <id> --wait --json` で実行完了まで待機
2. `record.status`, `record.stdout`, `record.stderr` を報告

**ユーザー: 「タイムアウトを伸ばして」**
1. `lr show <id> --json` で現在の設定を確認
2. `lr edit <id> --timeout <新しい値> --json` で更新
3. 変更結果を報告
