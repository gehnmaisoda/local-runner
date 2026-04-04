# LocalRunner

macOS 向けのローカルタスクスケジューラ。

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/daemon-Swift%206.1-orange" alt="Swift 6.1">
  <img src="https://img.shields.io/badge/cli-Bun%20%2B%20TypeScript-black" alt="Bun + TypeScript">
</p>

## 背景

開発マシンで定期タスクを動かしたいとき、選択肢はいくつかある。

- **Cloud Scheduler** — 認証やインフラの用意が必要。ローカルのスクリプトを動かすだけなのにオーバーヘッドが大きく、ベンダーごとに仕様も違う
- **cron** — シンプルだがログも通知もなく、Mac のスリープ中に逃したタスクは実行されない
- **launchd (plist)** — macOS ネイティブだが XML の手書き管理が手間

LocalRunner は launchd の上に構築し、macOS ネイティブの信頼性を保ちながら、ログ・通知・ネットワーク状態の考慮・CLI/Web UI を提供する。

|  | cron | launchd | Cloud Scheduler | **LocalRunner** |
|:---|:---:|:---:|:---:|:---:|
| スリープ復帰後のキャッチアップ | -- | 制限あり | N/A | タスク単位で設定可 |
| ネットワーク切断時の保留・復帰実行 | -- | -- | N/A | 自動 |
| 実行ログの永続化・閲覧 | 自前 | stdout/stderr のみ | コンソール | JSON + CLI/Web UI |
| 失敗時の通知 | 自前 | -- | 別サービス経由 | Slack Webhook |
| タスク定義 | crontab | XML plist | ベンダー固有 | YAML |
| 管理 UI | -- | -- | ベンダーコンソール | Web UI + CLI |
| 認証・インフラ | 不要 | 不要 | 必要 | 不要 |

## Quick Start

### 1. インストール

```bash
brew tap gehnmaisoda/local-runner
brew install local-runner
```

### 2. デーモンを起動

```bash
lr install   # LaunchAgent として登録・起動
lr doctor    # セットアップ診断
```

### 3. タスクを作成して動かす

```bash
lr create --name "hello" --command "echo hello from LocalRunner" --schedule-type hourly
lr run hello
lr logs hello --output
```

## Usage

### Coding Agent から自然言語で操作する (推奨)

LocalRunner の CLI は JSON 出力に対応しており、Claude Code / Codex / Cursor などの coding agent から自然言語でタスクを管理できる。Claude Code 向けには Skill (`/lr`) が付属している。

```
You: 毎朝9時にprojectsフォルダでgit fetchを全リポジトリに実行するタスクを作って
You: backup-dbのスケジュールを毎週月曜に変更して
You: 失敗してるタスクある？ログ見せて
```

YAML の書き方やスケジュール記法を覚える必要はない。会話の中で CLI が操作され、タスク定義が生成・更新される。

### Web UI

```bash
lr   # ブラウザが開く
```

作成したタスクの状態確認・実行履歴の閲覧・手動実行/停止を Web UI から行える。WebSocket によるリアルタイム更新。

### CLI

直接 CLI を使うこともできる。

```bash
lr list            # タスク一覧
lr status          # サマリー
lr run <id>        # 即座に実行
lr stop <id>       # 停止
lr toggle <id>     # 有効/無効切り替え
lr logs [id]       # 実行履歴
lr doctor          # セットアップ診断
```

## Features

- **Sleep/Wake Catch-up** — スリープ復帰時に逃したスケジュールを検知し、キャッチアップ実行。タスク単位で `catch_up: true/false` を設定可
- **Network-Aware Execution** — `NWPathMonitor` でネットワーク状態を監視。オフライン中のタスクは保留され、接続回復時に実行
- **Execution Log** — 実行ごとに stdout/stderr/終了コード/実行時間を JSON で永続化
- **Slack Notification** — 失敗・タイムアウト時に Slack Incoming Webhook で通知
- **Task Hot Reload** — `~/.config/local-runner/tasks/` 内の YAML 変更を自動検知・リロード
- **Flexible Scheduling** — `every_minute` / `hourly` / `daily` / `weekly` / `monthly` / `cron` 式に対応
- **Dotfiles 管理** — タスク定義は `~/.config/local-runner/tasks/*.yaml` に保存される。dotfiles リポジトリに含めれば、マシン移行時もタスク設定をそのまま持ち運べる

## License

MIT
