#!/usr/bin/env bun

import { listTasks, runTask, stopTask, showLogs, showStatus, toggleTask } from "./src/commands.ts";
import { startServer } from "./src/serve.ts";
import { install, uninstall, doctor } from "./src/launchagent.ts";

const args = process.argv.slice(2);
const command = args[0];

function printUsage() {
  console.log(`使い方: lr [コマンド] [オプション]

コマンド:
  (なし)            Web UI をブラウザで開く
  list              タスク一覧を表示
  status            サマリーを表示
  run <タスクID>    タスクを即座に実行
  stop <タスクID>   実行中のタスクを停止
  toggle <タスクID> タスクの有効/無効を切り替え
  logs [タスクID]   実行履歴を表示
  serve [ポート]    Web UI をブラウザを開かずに起動
  install           デーモンを LaunchAgent として登録
  uninstall         デーモンの LaunchAgent を解除
  doctor            セットアップの診断

オプション:
  -n, --limit <n>   ログ件数の上限 (デフォルト: 20)
  -h, --help        このヘルプを表示`);
}

async function main() {
  if (command === "-h" || command === "--help") {
    printUsage();
    process.exit(0);
  }

  // Default: open Web UI
  if (!command) {
    await startServer();
    return;
  }

  switch (command) {
    case "list":
    case "ls":
      await listTasks();
      break;

    case "status":
      await showStatus();
      break;

    case "run": {
      const taskId = args[1];
      if (!taskId) {
        console.error("使い方: lr run <タスクID>");
        process.exit(1);
      }
      await runTask(taskId);
      break;
    }

    case "stop": {
      const taskId = args[1];
      if (!taskId) {
        console.error("使い方: lr stop <タスクID>");
        process.exit(1);
      }
      await stopTask(taskId);
      break;
    }

    case "toggle": {
      const taskId = args[1];
      if (!taskId) {
        console.error("使い方: lr toggle <タスクID>");
        process.exit(1);
      }
      await toggleTask(taskId);
      break;
    }

    case "logs":
    case "log": {
      const taskId = args[1];
      const limitIdx = args.indexOf("-n") !== -1 ? args.indexOf("-n") : args.indexOf("--limit");
      const limit = limitIdx !== -1 ? parseInt(args[limitIdx + 1] ?? "20", 10) : 20;
      await showLogs(taskId, limit);
      break;
    }

    case "serve": {
      const port = args[1] ? parseInt(args[1], 10) : undefined;
      await startServer(port);
      break;
    }

    case "install":
      await install();
      break;

    case "uninstall":
      await uninstall();
      break;

    case "doctor":
      await doctor();
      break;

    default:
      console.error(`不明なコマンド: ${command}`);
      printUsage();
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
