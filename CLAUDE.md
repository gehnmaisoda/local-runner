# LocalRunner - Claude Code 開発ガイド

## プロジェクト概要

macOS ローカルジョブランナー。開発者向けタスクスケジューラ。
Daemon（Swift / LaunchAgent）がスケジューリング・実行を担当し、CLI + Web UI（Bun / TypeScript）が操作インターフェースを提供する2プロセス構成。

## ディレクトリ構成

```
local-runner/
├── daemon/                   # Swift daemon
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Core/             # 共有モデル (TaskDefinition, Schedule, CronExpression, IPCProtocol 等)
│   │   ├── DaemonLib/        # デーモンライブラリ (Scheduler, Executor, LogStore, IPCServer, NetworkMonitor 等)
│   │   └── Daemon/           # デーモンエントリーポイント (main.swift)
│   ├── Tests/
│   │   ├── CoreTests/
│   │   └── DaemonTests/
│   └── Resources/
│       └── com.gehnmaisoda.local-runner.daemon.plist
│
├── cli/                      # Bun CLI + Web UI
│   ├── index.ts              # エントリーポイント (lr コマンド)
│   ├── package.json
│   └── src/
│       ├── ipc.ts            # IPC クライアント (Unix Domain Socket)
│       ├── commands.ts       # CLI コマンド実装
│       ├── serve.ts          # Web UI サーバー (HTTP + WebSocket)
│       └── launchagent.ts    # LaunchAgent 管理 (install/uninstall/doctor)
│
├── Makefile                  # 全体オーケストレーション
└── CLAUDE.md
```

## アーキテクチャ

```
Daemon (Swift, LaunchAgent 常駐)
  ├─ TaskScheduler   — cron/スケジュール管理, 1秒間隔チェック
  ├─ TaskExecutor    — /bin/zsh -l -c でコマンド実行 (タイムアウト対応)
  ├─ LogStore        — 実行ログ永続化 (JSON)
  ├─ SlackNotifier   — 失敗/タイムアウト時 Slack 通知
  ├─ WakeDetector    — スリープ復帰時のキャッチアップ
  ├─ NetworkMonitor  — ネットワーク状態監視 (NWPathMonitor)
  └─ IPCServer       — Unix Domain Socket サーバー

CLI + Web UI (Bun / TypeScript)
  ├─ IPC Client      — Daemon と Unix Domain Socket で通信
  ├─ CLI commands    — lr list, lr run, lr stop, lr logs 等
  ├─ HTTP Server     — localhost で Web UI 提供 (空きポート自動採番)
  └─ LaunchAgent     — Daemon の install/uninstall/doctor
```

## IPC プロトコル

- ソケットパス: `~/Library/Application Support/LocalRunner/daemon.sock` (DEV: `LocalRunner-Dev`)
- ワイヤーフォーマット: 4バイト ビッグエンディアン長プレフィックス + JSON
- 日付エンコーディング: ISO 8601
- アクション: `list_tasks`, `run_task`, `stop_task`, `get_history`, `reload`, `save_task`, `delete_task`, `toggle_task`, `get_settings`, `update_settings`, `subscribe`

## ビルド・実行コマンド

### Makefile (ルート)

- `make daemon` — デバッグビルド & Daemon 実行 (フォアグラウンド)
- `make test` — テスト実行
- `make build` — Daemon リリースビルド
- `make install` — リリースビルド & LaunchAgent 登録
- `make clean` — クリーン

### CLI (Bun)

- `cd cli && bun run index.ts` — Web UI 起動 (デフォルト)
- `cd cli && bun run index.ts list` — タスク一覧
- `cd cli && bun run index.ts doctor` — 診断

## 技術スタック

### Daemon (Swift)
- Swift 6.1 / Swift Package Manager
- Xcode IDE は使わない (エディタ + ターミナル)
- 対象: macOS 13+
- YAML パース: Yams
- IPC: Unix Domain Socket (長さプレフィックス付き JSON)

### CLI + Web UI (Bun / TypeScript)
- Bun ランタイム
- Web UI: Bun.serve() + WebSocket + インライン HTML/JS
- LaunchAgent 管理: launchctl CLI 経由

## コーディング規約

### Swift (Daemon / Core)
- Swift 6.1 の concurrency モデルに従う

### TypeScript (CLI)
- strict モード
- ESM

## アプリの起動・停止

- `make daemon` や `pkill` などのプロセス管理はユーザーが行う。ユーザーからの指示がない限り Claude は実行しない。

## テスト方針

- 純粋関数や重要なロジックには積極的にユニットテストを書く
- Swift テストは `daemon/Tests/CoreTests/` に配置し、Swift Testing (`import Testing`) を使用する
- テストの `@Test()` ラベルやコメントは英語で書く

## タスク管理

- **GitHub Issues で管理する**（`gh issue list` / `gh issue create` 等を活用）
