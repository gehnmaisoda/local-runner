# アーキテクチャ

## プロセス構成

LocalRunner は 2 つのプロセスで構成される。

| プロセス | 言語 | 役割 |
|:---|:---|:---|
| `local-runnerd` | Swift | スケジューリング・タスク実行・ログ保存・通知 |
| `lr` | Bun / TypeScript | CLI 操作・Web UI 提供 |

Daemon は LaunchAgent として常駐し、CLI / Web UI は必要なときだけ起動する。

## 通信経路

```
┌──────────────────────────────────────────────────────┐
│  CLI (lr list, lr run, ...)                          │
│    └─── Unix Domain Socket ──→ daemon.sock ──→ Daemon│
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Web UI                                              │
│    ブラウザ ←─ WebSocket ──→ lr serve (HTTP サーバー)  │
│                                └─── Unix Domain Socket│
│                                       └──→ daemon.sock│
│                                             └──→ Daemon│
└──────────────────────────────────────────────────────┘
```

### CLI → Daemon

CLI コマンドは Daemon と直接 Unix Domain Socket で通信する。

```
lr list
  → IPC Client が daemon.sock に接続
  → JSON リクエスト送信: {"action": "list_tasks"}
  → Daemon が JSON レスポンスを返却
  → CLI がフォーマットして stdout に出力
```

- 通信は 1 リクエスト / 1 レスポンスの同期的なやりとり
- コマンド完了後に接続を閉じる

### Web UI → Daemon

Web UI はブラウザと Daemon の間に HTTP サーバー (`lr serve`) が介在する。

```
ブラウザ ←──WebSocket──→ lr serve ←──Unix Domain Socket──→ Daemon
```

1. `lr serve` が localhost で HTTP サーバーを起動し、ブラウザを開く
2. ブラウザは WebSocket でサーバーに接続
3. サーバーはブラウザからのリクエストを daemon.sock に中継する
4. Daemon の `subscribe` アクションでリアルタイム更新を受け取り、WebSocket 経由でブラウザに push する

2 段構成にしている理由:
- ブラウザから Unix Domain Socket に直接アクセスできない
- `lr serve` が WebSocket ↔ Unix Domain Socket のブリッジとして機能する

## IPC プロトコル (Unix Domain Socket)

- ソケットパス: `~/Library/Application Support/LocalRunner/daemon.sock`
- ワイヤーフォーマット: 4 バイト ビッグエンディアン長さプレフィックス + JSON ペイロード
- 日付: ISO 8601

### アクション一覧

| アクション | 説明 |
|:---|:---|
| `list_tasks` | タスク一覧 |
| `run_task` | タスク実行 |
| `stop_task` | タスク停止 |
| `get_history` | 実行履歴取得 |
| `reload` | タスク定義再読み込み |
| `save_task` | タスク保存 (作成・更新) |
| `delete_task` | タスク削除 |
| `toggle_task` | 有効/無効切り替え |
| `get_settings` | 設定取得 |
| `update_settings` | 設定変更 |
| `get_version` | バージョン取得 |
| `subscribe` | リアルタイム更新の購読 (Web UI 用) |
