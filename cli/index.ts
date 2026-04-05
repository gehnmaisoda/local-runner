#!/usr/bin/env bun

import { parseArgs } from "./src/args.ts";
import {
  listTasks, showTask, createTask, editTask, deleteTask,
  runTask, stopTask, toggleTask, showLogs, showStatus,
  configGet, configSet, reloadTasks,
  CLIError, EXIT, parsePositiveInt,
} from "./src/commands.ts";
import { startServer } from "./src/serve.ts";
import { install, uninstall, doctor } from "./src/launchagent.ts";
import { createClient } from "./src/ipc.ts";
import { checkForUpdates } from "./src/update-check.ts";
import { readFileSync } from "fs";
import { resolve } from "path";

declare const __EMBEDDED_VERSION__: string | undefined;

const CLI_VERSION = typeof __EMBEDDED_VERSION__ === "string"
  ? __EMBEDDED_VERSION__
  : readFileSync(resolve(import.meta.dir, "../VERSION"), "utf-8").trim();

const args = parseArgs(process.argv.slice(2));
const command = args.positionals[0];
const json = args.flags.has("json");

// --- Help texts ---

const MAIN_HELP = `使い方: lr [コマンド] [オプション]

コマンド:
  (なし)              Web UI をブラウザで開く
  list                タスク一覧を表示
  show <タスクID>     タスクの詳細を表示
  create              タスクを新規作成
  edit <タスクID>     タスクを編集
  delete <タスクID>   タスクを削除
  run <タスクID>      タスクを即座に実行
  stop <タスクID>     実行中のタスクを停止
  toggle <タスクID>   タスクの有効/無効を切り替え
  logs [タスクID]     実行履歴を表示
  status              サマリーを表示
  config get          設定を表示
  config set <k> <v>  設定を変更
  reload              タスク定義を再読み込み
  serve [ポート]      Web UI をブラウザを開かずに起動
  install             デーモンを LaunchAgent として登録
  uninstall           デーモンの LaunchAgent を解除 (--purge でデータも全削除)
  doctor              セットアップの診断

共通オプション:
  --json              JSON で出力 (スクリプトや LLM から呼び出す場合は常に指定推奨)
  -h, --help          ヘルプを表示

LLM/スクリプト連携:
  全コマンドに --json を付けると構造化 JSON を stdout に出力します。
  エラー時も {"success":false,"error":"..."} 形式で返します。
  削除時は --yes を併用して確認プロンプトをスキップしてください。`;

const HELP: Record<string, string> = {
  create: `タスクを新規作成します。

使い方: lr create --name <名前> --command <コマンド> --schedule-type <タイプ> [オプション]

スケジュール:
  --schedule-type <type>  every_minute | hourly | daily | weekly | monthly | cron
  --time "HH:mm"          daily/weekly/monthly の実行時刻
  --minute <0-59>          hourly の実行分
  --weekdays "1,3,5"       weekly の曜日 (1=月..7=日)
  --month-days "1,15,-1"   monthly の日 (-1=月末)
  --cron "<expression>"    cron 式

オプション:
  --id <id>                タスクID (省略時は自動生成)
  --description <説明>     タスクの説明
  --working-dir <path>     作業ディレクトリ
  --catch-up / --no-catch-up  スリープ復帰時の実行 (デフォルト: on)
  --notify / --no-notify   失敗時 Slack 通知 (デフォルト: off)
  --timeout <秒>           タイムアウト
  --disabled               無効状態で作成
  --json                   JSON で出力

例:
  lr create --name "DB バックアップ" --command "pg_dump mydb > dump.sql" --schedule-type daily --time "04:00"
  lr create --name "ヘルスチェック" --command "curl -sf localhost:8080/health" --schedule-type cron --cron "*/5 * * * *"`,

  edit: `タスクを編集します。指定したフィールドだけを更新します。

使い方: lr edit <タスクID> [オプション]

オプション:
  --name <名前>            タスク名
  --description <説明>     タスクの説明
  --command <コマンド>     実行コマンド
  --working-dir <path>     作業ディレクトリ
  --schedule-type <type>   スケジュールタイプを変更 (全スケジュール再設定)
  --time "HH:mm"           実行時刻
  --minute <0-59>          hourly の実行分
  --weekdays "1,3,5"       weekly の曜日
  --month-days "1,15,-1"   monthly の日
  --cron "<expression>"    cron 式
  --catch-up / --no-catch-up  スリープ復帰時の実行
  --notify / --no-notify   失敗時 Slack 通知
  --timeout <秒>           タイムアウト
  --disabled               無効にする
  --json                   JSON で出力

例:
  lr edit backup --command "rsync -av --delete ~/docs /mnt/backup/"
  lr edit backup --timeout 1200 --notify
  lr edit backup --schedule-type weekly --weekdays "1,5" --time "02:00"`,

  delete: `タスクを削除します。

使い方: lr delete <タスクID> [オプション]

オプション:
  -y, --yes   確認をスキップ
  --json      JSON で出力`,

  run: `タスクを即座に実行します。

使い方: lr run <タスクID> [オプション]

オプション:
  --wait   実行完了まで待機し、結果を返す
  --json   JSON で出力

例:
  lr run backup
  lr run backup --wait --json`,

  stop: `実行中のタスクを停止します。

使い方: lr stop <タスクID> [オプション]

オプション:
  --json   JSON で出力`,

  toggle: `タスクの有効/無効を切り替えます。

使い方: lr toggle <タスクID> [オプション]

オプション:
  --json   JSON で出力`,

  logs: `実行履歴を表示します。

使い方: lr logs [タスクID] [オプション]

オプション:
  -n, --limit <N>   表示件数 (デフォルト: 20)
  --last <N>         表示件数 (--limit のエイリアス)
  --output           stdout/stderr を表示
  --json             JSON で出力

例:
  lr logs
  lr logs backup --output
  lr logs backup --output --last 3`,

  show: `タスクの詳細を表示します。

使い方: lr show <タスクID> [オプション]

オプション:
  --json   JSON で出力`,

  status: `タスクのサマリーを表示します。

使い方: lr status [オプション]

オプション:
  --json   JSON で出力`,

  config: `設定を表示・変更します。

使い方:
  lr config get              設定を表示
  lr config set <key> <value>  設定を変更

設定キー:
  default_timeout      デフォルトタイムアウト (秒)
  slack_webhook_url    Slack Webhook URL

オプション:
  --json   JSON で出力

例:
  lr config get
  lr config set default_timeout 1800
  lr config set slack_webhook_url "https://hooks.slack.com/services/..."`,

  reload: `タスク定義ファイルを再読み込みします。

使い方: lr reload [オプション]

オプション:
  --json   JSON で出力`,

  list: `タスク一覧を表示します。

使い方: lr list [オプション]

オプション:
  --json   JSON で出力`,

  doctor: `セットアップの診断を行います。

使い方: lr doctor [オプション]

オプション:
  --json   JSON で出力`,
};

// --- Main ---

function showHelp(cmd?: string) {
  if (cmd && HELP[cmd]) {
    console.log(HELP[cmd]);
  } else {
    console.log(MAIN_HELP);
  }
}

async function main() {
  // Global --version
  if (args.flags.has("version") && !command) {
    console.log(`lr ${CLI_VERSION}`);
    try {
      const client = await createClient();
      const res = await client.send({ action: "get_version" }, 1000);
      if (res.version) {
        console.log(`local-runnerd ${res.version}`);
      }
      client.close();
    } catch {
      console.log("local-runnerd (未接続)");
    }
    process.exit(EXIT.SUCCESS);
  }

  // Global --help
  if (args.flags.has("help") && !command) {
    showHelp();
    process.exit(EXIT.SUCCESS);
  }

  // Default: open Web UI
  if (!command) {
    checkForUpdates(CLI_VERSION);
    await startServer();
    return;
  }

  // Subcommand --help
  if (args.flags.has("help")) {
    showHelp(command);
    process.exit(EXIT.SUCCESS);
  }

  switch (command) {
    case "list":
    case "ls":
      await listTasks(json);
      break;

    case "show": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr show <タスクID>", EXIT.VALIDATION);
      await showTask(taskId, json);
      break;
    }

    case "create":
      await createTask(args.flags, args.options);
      break;

    case "edit": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr edit <タスクID>", EXIT.VALIDATION);
      await editTask(taskId, args.flags, args.options);
      break;
    }

    case "delete": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr delete <タスクID>", EXIT.VALIDATION);
      await deleteTask(taskId, json, args.flags.has("yes"));
      break;
    }

    case "run": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr run <タスクID>", EXIT.VALIDATION);
      await runTask(taskId, json, args.flags.has("wait"));
      break;
    }

    case "stop": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr stop <タスクID>", EXIT.VALIDATION);
      await stopTask(taskId, json);
      break;
    }

    case "toggle": {
      const taskId = args.positionals[1];
      if (!taskId) throw new CLIError("使い方: lr toggle <タスクID>", EXIT.VALIDATION);
      await toggleTask(taskId, json);
      break;
    }

    case "logs":
    case "log": {
      const taskId = args.positionals[1];
      const limitStr = args.options.get("last") ?? args.options.get("limit");
      const limit = limitStr ? parsePositiveInt(limitStr, "--limit") : 20;
      await showLogs(taskId, json, args.flags.has("output"), limit);
      break;
    }

    case "status":
      await showStatus(json);
      break;

    case "config": {
      const sub = args.positionals[1];
      if (sub === "get") {
        await configGet(json);
      } else if (sub === "set") {
        const key = args.positionals[2];
        const value = args.positionals[3];
        if (!key || !value) {
          throw new CLIError("使い方: lr config set <key> <value>", EXIT.VALIDATION);
        }
        await configSet(key, value, json);
      } else {
        throw new CLIError(
          "使い方: lr config get | lr config set <key> <value>",
          EXIT.VALIDATION
        );
      }
      break;
    }

    case "reload":
      await reloadTasks(json);
      break;

    case "serve": {
      const port = args.positionals[1] ? parseInt(args.positionals[1], 10) : undefined;
      await startServer(port);
      break;
    }

    case "install":
      await install();
      break;

    case "uninstall":
      await uninstall(args.flags.has("purge"));
      break;

    case "doctor":
      await doctor(json);
      break;

    default:
      throw new CLIError(`不明なコマンド: ${command}`, EXIT.VALIDATION);
  }
}

main().catch((err) => {
    const message = err instanceof Error ? err.message : String(err);
    const exitCode = err instanceof CLIError ? err.exitCode : EXIT.GENERAL;

    if (json) {
      console.log(JSON.stringify({ success: false, error: message }));
    } else {
      console.error(`エラー: ${message}`);
    }

    process.exit(exitCode);
  });
