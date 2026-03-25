#!/usr/bin/env bun

import { listTasks, runTask, stopTask, showLogs, showStatus, toggleTask } from "./src/commands.ts";
import { startServer } from "./src/serve.ts";
import { install, uninstall, doctor } from "./src/launchagent.ts";

const args = process.argv.slice(2);
const command = args[0];

function printUsage() {
  console.log(`Usage: lr [command] [options]

Commands:
  (none)            Open Web UI in browser
  list              List all tasks
  status            Show summary status
  run <task-id>     Run a task immediately
  stop <task-id>    Stop a running task
  toggle <task-id>  Enable/disable a task
  logs [task-id]    Show execution history
  serve [port]      Start Web UI without opening browser
  install           Install daemon as LaunchAgent
  uninstall         Remove daemon LaunchAgent
  doctor            Diagnose setup issues

Options:
  -n, --limit <n>   Limit log entries (default: 20)
  -h, --help        Show this help`);
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
        console.error("Usage: lr run <task-id>");
        process.exit(1);
      }
      await runTask(taskId);
      break;
    }

    case "stop": {
      const taskId = args[1];
      if (!taskId) {
        console.error("Usage: lr stop <task-id>");
        process.exit(1);
      }
      await stopTask(taskId);
      break;
    }

    case "toggle": {
      const taskId = args[1];
      if (!taskId) {
        console.error("Usage: lr toggle <task-id>");
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
      console.error(`Unknown command: ${command}`);
      printUsage();
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
