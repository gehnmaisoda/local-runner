import { createClient, type IPCClient, type TaskStatus, type ExecutionRecord } from "./ipc.ts";

// --- Formatters ---

export function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  const d = new Date(iso);
  return d.toLocaleString("ja-JP", {
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function formatDuration(record: ExecutionRecord): string {
  if (!record.finishedAt) return "-";
  const ms =
    new Date(record.finishedAt).getTime() -
    new Date(record.startedAt).getTime();
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const m = Math.floor(ms / 60000);
  const s = Math.floor((ms % 60000) / 1000);
  return `${m}m${s}s`;
}

export function statusIcon(status: TaskStatus): string {
  if (status.isRunning) return "\u25B6"; // running
  if (!status.task.enabled) return "\u25CB"; // disabled
  if (status.lastRun?.status === "failure") return "\u2717"; // failed
  if (status.lastRun?.status === "timeout") return "\u23F0"; // timeout
  if (status.lastRun?.status === "success") return "\u2713"; // success
  return "\u25CB"; // no history
}

export function pad(s: string, len: number): string {
  return s.length >= len ? s.substring(0, len) : s + " ".repeat(len - s.length);
}

// --- Commands ---

async function withClient<T>(fn: (client: IPCClient) => Promise<T>): Promise<T> {
  const client = await createClient();
  try {
    return await fn(client);
  } finally {
    client.close();
  }
}

export async function listTasks() {
  await withClient(async (client) => {
    const res = await client.send({ action: "list_tasks" });
    if (!res.success || !res.tasks) {
      console.error("エラー:", res.error ?? "タスクが返されませんでした");
      return;
    }
    if (res.tasks.length === 0) {
      console.log("タスクが定義されていません。");
      return;
    }

    console.log(
      `${pad("状態", 7)} ${pad("ID", 20)} ${pad("名前", 24)} ${pad("次回実行", 18)} ${pad("前回", 8)}`
    );
    console.log("-".repeat(80));

    for (const t of res.tasks) {
      const icon = statusIcon(t);
      const lastStatus = t.lastRun
        ? t.lastRun.status === "success"
          ? `\u2713 ${formatDuration(t.lastRun)}`
          : `\u2717 ${formatDuration(t.lastRun)}`
        : "-";
      console.log(
        `  ${pad(icon, 5)} ${pad(t.task.id, 20)} ${pad(t.task.name, 24)} ${pad(formatDate(t.nextRunAt), 18)} ${lastStatus}`
      );
    }
  });
}

export async function runTask(taskId: string) {
  await withClient(async (client) => {
    const res = await client.send({ action: "run_task", taskId });
    if (res.success) {
      console.log(`タスク "${taskId}" を開始しました。`);
    } else {
      console.error("エラー:", res.error);
    }
  });
}

export async function stopTask(taskId: string) {
  await withClient(async (client) => {
    const res = await client.send({ action: "stop_task", taskId });
    if (res.success) {
      console.log(`タスク "${taskId}" を停止しました。`);
    } else {
      console.error("エラー:", res.error);
    }
  });
}

export async function showLogs(taskId?: string, limit = 20) {
  await withClient(async (client) => {
    const res = await client.send({
      action: "get_history",
      taskId,
      limit,
    });
    if (!res.success || !res.history) {
      console.error("エラー:", res.error ?? "履歴が返されませんでした");
      return;
    }
    if (res.history.length === 0) {
      console.log("実行履歴がありません。");
      return;
    }

    console.log(
      `${pad("状態", 8)} ${pad("タスク", 20)} ${pad("開始", 18)} ${pad("所要時間", 10)} 終了コード`
    );
    console.log("-".repeat(70));

    for (const r of res.history) {
      const icon = r.status === "success" ? "\u2713" : r.status === "timeout" ? "\u23F0" : r.status === "failure" ? "\u2717" : "\u25B6";
      console.log(
        `  ${pad(icon, 6)} ${pad(r.taskName, 20)} ${pad(formatDate(r.startedAt), 18)} ${pad(formatDuration(r), 10)} ${r.exitCode ?? "-"}`
      );
    }
  });
}

export async function showStatus() {
  await withClient(async (client) => {
    const res = await client.send({ action: "list_tasks" });
    if (!res.success) {
      console.error("エラー:", res.error);
      return;
    }
    const tasks = res.tasks ?? [];
    const running = tasks.filter((t) => t.isRunning);
    const enabled = tasks.filter((t) => t.task.enabled);

    console.log(`タスク: ${tasks.length} 件中 ${enabled.length} 件有効, ${running.length} 件実行中`);

    if (running.length > 0) {
      console.log("\n実行中:");
      for (const t of running) {
        console.log(`  \u25B6 ${t.task.name} (${t.task.id})`);
      }
    }

    const next = enabled
      .filter((t) => t.nextRunAt)
      .sort(
        (a, b) =>
          new Date(a.nextRunAt!).getTime() - new Date(b.nextRunAt!).getTime()
      );
    if (next.length > 0) {
      console.log("\n予定:");
      for (const t of next.slice(0, 5)) {
        console.log(`  ${formatDate(t.nextRunAt)} - ${t.task.name}`);
      }
    }
  });
}

export async function toggleTask(taskId: string) {
  await withClient(async (client) => {
    const res = await client.send({ action: "toggle_task", taskId });
    if (res.success) {
      console.log(`タスク "${taskId}" の有効/無効を切り替えました。`);
    } else {
      console.error("エラー:", res.error);
    }
  });
}
