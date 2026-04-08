import { createClient, type IPCClient, type TaskStatus, type ExecutionRecord, type Schedule, type TaskDefinition, type GlobalSettings, type LogEntry } from "./ipc.ts";
import { createInterface } from "readline";

// --- Exit codes ---

export const EXIT = {
  SUCCESS: 0,
  GENERAL: 1,
  NOT_FOUND: 2,
  NO_DAEMON: 3,
  VALIDATION: 4,
} as const;

export class CLIError extends Error {
  constructor(message: string, public exitCode: number = EXIT.GENERAL) {
    super(message);
  }
}

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

/** ISO 日付文字列を "YYYY-MM-DD HH:mm:ss" 形式に変換する。 */
export function formatTimestamp(iso: string): string {
  const d = new Date(iso);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
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

const WEEKDAY_NAMES = ["月", "火", "水", "木", "金", "土", "日"];

export function formatSchedule(schedule: Schedule): string {
  switch (schedule.type) {
    case "every_minute":
      return "毎分";
    case "hourly":
      return `毎時 ${schedule.minute ?? 0}分`;
    case "daily":
      return `毎日 ${schedule.time ?? "00:00"}`;
    case "weekly": {
      const days = schedule.weekdays ?? (schedule.weekday ? [schedule.weekday] : [1]);
      const dayStr = days.map(d => WEEKDAY_NAMES[d - 1] ?? String(d)).join(",");
      return `毎週 ${dayStr}曜 ${schedule.time ?? "00:00"}`;
    }
    case "monthly": {
      const days = schedule.month_days ?? [1];
      const dayStr = days.map(d => d === -1 ? "末日" : `${d}日`).join(",");
      return `毎月 ${dayStr} ${schedule.time ?? "00:00"}`;
    }
    case "cron":
      return `cron: ${schedule.expression ?? ""}`;
    default:
      return schedule.type;
  }
}

export function generateId(name: string): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .substring(0, 50);
  return slug || `task-${Date.now()}`;
}

// --- Schedule builders ---

export function buildSchedule(options: Map<string, string>): Schedule {
  const type = options.get("schedule-type");
  if (!type) throw new CLIError("--schedule-type は必須です", EXIT.VALIDATION);

  const validTypes = ["every_minute", "hourly", "daily", "weekly", "monthly", "cron"];
  if (!validTypes.includes(type)) {
    throw new CLIError(
      `不正なスケジュールタイプ: ${type} (${validTypes.join(" | ")})`,
      EXIT.VALIDATION
    );
  }

  const schedule: Schedule = { type };

  switch (type) {
    case "every_minute":
      break;
    case "hourly": {
      const min = parseInt(options.get("minute") ?? "0", 10);
      if (isNaN(min) || min < 0 || min > 59) {
        throw new CLIError("--minute は 0-59 の整数を指定してください", EXIT.VALIDATION);
      }
      schedule.minute = min;
      break;
    }
    case "daily":
      schedule.time = options.get("time") ?? "00:00";
      break;
    case "weekly":
      schedule.time = options.get("time") ?? "00:00";
      if (options.has("weekdays")) {
        schedule.weekdays = options.get("weekdays")!.split(",").map(Number);
      } else {
        schedule.weekdays = [1];
      }
      break;
    case "monthly":
      schedule.time = options.get("time") ?? "00:00";
      if (options.has("month-days")) {
        schedule.month_days = options.get("month-days")!.split(",").map(Number);
      } else {
        schedule.month_days = [1];
      }
      break;
    case "cron":
      if (!options.has("cron")) {
        throw new CLIError("cron タイプには --cron が必須です", EXIT.VALIDATION);
      }
      schedule.expression = options.get("cron");
      break;
  }

  return schedule;
}

export function applyScheduleEdits(existing: Schedule, options: Map<string, string>): Schedule {
  if (options.has("schedule-type")) {
    return buildSchedule(options);
  }
  const updated = { ...existing };
  if (options.has("time")) updated.time = options.get("time");
  if (options.has("minute")) updated.minute = parseInt(options.get("minute")!, 10);
  if (options.has("weekdays")) updated.weekdays = options.get("weekdays")!.split(",").map(Number);
  if (options.has("month-days")) updated.month_days = options.get("month-days")!.split(",").map(Number);
  if (options.has("cron")) updated.expression = options.get("cron");
  return updated;
}

// --- Constants ---

const DAEMON_CONNECTION_ERROR = "デーモンへの接続に失敗しました。デーモンは起動していますか？";
const WAIT_TIMEOUT_MS = 86400000; // 24 hours

// --- Helpers ---

export function parsePositiveInt(value: string, label: string): number {
  const num = parseInt(value, 10);
  if (isNaN(num) || num <= 0) {
    throw new CLIError(`${label} は正の整数を指定してください`, EXIT.VALIDATION);
  }
  return num;
}

async function withClient<T>(fn: (client: IPCClient) => Promise<T>): Promise<T> {
  let client: IPCClient;
  try {
    client = await createClient();
  } catch {
    throw new CLIError(DAEMON_CONNECTION_ERROR, EXIT.NO_DAEMON);
  }
  try {
    return await fn(client);
  } finally {
    client.close();
  }
}

async function confirm(message: string): Promise<boolean> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => {
    rl.question(message, (answer) => {
      rl.close();
      resolve(answer.trim().toLowerCase() === "y");
    });
  });
}

export function statusLabel(s: string): string {
  switch (s) {
    case "success": return "成功";
    case "failure": return "失敗";
    case "timeout": return "タイムアウト";
    case "running": return "実行中";
    case "stopped": return "停止";
    default: return s;
  }
}

// --- Commands ---

export async function listTasks(json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "list_tasks" });
    if (!res.success || !res.tasks) {
      throw new CLIError(res.error ?? "タスクが返されませんでした", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify(res.tasks));
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

export async function showTask(taskId: string, json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "list_tasks" });
    if (!res.success || !res.tasks) {
      throw new CLIError(res.error ?? "タスク一覧の取得に失敗しました", EXIT.GENERAL);
    }
    const t = res.tasks.find(s => s.task.id === taskId);
    if (!t) {
      throw new CLIError(`タスク '${taskId}' が見つかりません`, EXIT.NOT_FOUND);
    }

    if (json) {
      console.log(JSON.stringify(t));
      return;
    }

    const task = t.task;
    const state = t.isRunning ? "実行中" : task.enabled ? "待機中" : "無効";
    const lastRunInfo = t.lastRun
      ? `${formatDate(t.lastRun.startedAt)} (${statusLabel(t.lastRun.status)}, ${formatDuration(t.lastRun)})`
      : "-";

    console.log(`名前:         ${task.name}`);
    console.log(`ID:           ${task.id}`);
    if (task.description) console.log(`説明:         ${task.description}`);
    console.log(`コマンド:     ${task.command}`);
    if (task.working_directory) console.log(`ディレクトリ: ${task.working_directory}`);
    console.log(`スケジュール: ${formatSchedule(task.schedule)}`);
    console.log(`有効:         ${task.enabled ? "はい" : "いいえ"}`);
    console.log(`キャッチアップ: ${task.catch_up ? "はい" : "いいえ"}`);
    console.log(`Slack通知:    ${task.slack_notify ? "はい" : "いいえ"}`);
    if (task.slack_mentions?.length) {
      console.log(`メンション:   ${task.slack_mentions.join(", ")}`);
    }
    console.log(`タイムアウト: ${task.timeout != null ? `${task.timeout}秒` : "(デフォルト)"}`);
    console.log(`状態:         ${state}`);
    console.log(`次回実行:     ${formatDate(t.nextRunAt)}`);
    console.log(`前回実行:     ${lastRunInfo}`);
  });
}

export async function createTask(flags: Set<string>, options: Map<string, string>) {
  const json = flags.has("json");

  const name = options.get("name");
  const command = options.get("command");
  if (!name) throw new CLIError("--name は必須です", EXIT.VALIDATION);
  if (!command) throw new CLIError("--command は必須です", EXIT.VALIDATION);

  const schedule = buildSchedule(options);
  const id = options.get("id") ?? generateId(name);

  const task: TaskDefinition = {
    id,
    name,
    description: options.get("description"),
    command,
    working_directory: options.get("working-dir"),
    schedule,
    enabled: !flags.has("disabled"),
    catch_up: !flags.has("no-catch-up"),
    slack_notify: !flags.has("no-notify"),
    timeout: options.has("timeout") ? parsePositiveInt(options.get("timeout")!, "--timeout") : undefined,
  };

  await withClient(async (client) => {
    const res = await client.send({ action: "save_task", task });
    if (!res.success) {
      throw new CLIError(res.error ?? "タスクの作成に失敗しました", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify({ success: true, task }));
    } else {
      console.log(`タスク "${task.name}" (${task.id}) を作成しました。`);
    }
  });
}

export async function editTask(taskId: string, flags: Set<string>, options: Map<string, string>) {
  const json = flags.has("json");

  await withClient(async (client) => {
    // Get current task
    const listRes = await client.send({ action: "list_tasks" });
    if (!listRes.success || !listRes.tasks) {
      throw new CLIError("タスク一覧の取得に失敗しました", EXIT.GENERAL);
    }
    const taskStatus = listRes.tasks.find(t => t.task.id === taskId);
    if (!taskStatus) {
      throw new CLIError(`タスク '${taskId}' が見つかりません`, EXIT.NOT_FOUND);
    }

    const task: TaskDefinition = { ...taskStatus.task };

    // Apply field changes
    if (options.has("name")) task.name = options.get("name")!;
    if (options.has("description")) task.description = options.get("description")!;
    if (options.has("command")) task.command = options.get("command")!;
    if (options.has("working-dir")) task.working_directory = options.get("working-dir")!;
    if (options.has("timeout")) task.timeout = parsePositiveInt(options.get("timeout")!, "--timeout");
    if (flags.has("catch-up")) task.catch_up = true;
    if (flags.has("no-catch-up")) task.catch_up = false;
    if (flags.has("notify")) task.slack_notify = true;
    if (flags.has("no-notify")) task.slack_notify = false;
    if (flags.has("disabled")) task.enabled = false;

    // Apply schedule edits
    task.schedule = applyScheduleEdits(task.schedule, options);

    const res = await client.send({ action: "save_task", task });
    if (!res.success) {
      throw new CLIError(res.error ?? "タスクの更新に失敗しました", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify({ success: true, task }));
    } else {
      console.log(`タスク "${task.name}" (${task.id}) を更新しました。`);
    }
  });
}

export async function deleteTask(taskId: string, json: boolean, yes: boolean) {
  await withClient(async (client) => {
    // Get task name for confirmation message
    if (!yes && !json) {
      const listRes = await client.send({ action: "list_tasks" });
      const t = listRes.tasks?.find(s => s.task.id === taskId);
      const label = t ? `"${t.task.name}" (${taskId})` : `"${taskId}"`;
      const confirmed = await confirm(`タスク ${label} を削除しますか？ [y/N]: `);
      if (!confirmed) {
        console.log("キャンセルしました。");
        return;
      }
    }

    const res = await client.send({ action: "delete_task", taskId });
    if (!res.success) {
      throw new CLIError(res.error ?? "タスクの削除に失敗しました", EXIT.NOT_FOUND);
    }

    if (json) {
      console.log(JSON.stringify({ success: true }));
    } else {
      console.log("削除しました。");
    }
  });
}

export async function runTask(taskId: string, json: boolean, wait: boolean) {
  if (!wait) {
    await withClient(async (client) => {
      const res = await client.send({ action: "run_task", taskId });
      if (!res.success) {
        throw new CLIError(res.error ?? `タスク '${taskId}' の実行に失敗しました`, EXIT.NOT_FOUND);
      }
      if (json) {
        console.log(JSON.stringify({ success: true }));
      } else {
        console.log(`タスク "${taskId}" を開始しました。`);
      }
    });
    return;
  }

  // --wait mode: withClient を使わず直接管理する（subscribe + 完了通知待ちで接続を維持する必要があるため）
  let client: IPCClient;
  try {
    client = await createClient();
  } catch {
    throw new CLIError(DAEMON_CONNECTION_ERROR, EXIT.NO_DAEMON);
  }

  try {
    // Subscribe first to avoid missing the completion notification
    await client.send({ action: "subscribe" });

    const completionPromise = new Promise<ExecutionRecord>((resolve, reject) => {
      client.onNotify((notification) => {
        if (
          notification.event === "task_completed" &&
          notification.taskId === taskId &&
          notification.record
        ) {
          resolve(notification.record);
        }
      });
      client.onDisconnect = () =>
        reject(new CLIError("デーモンとの接続が切断されました", EXIT.NO_DAEMON));
      setTimeout(
        () => reject(new CLIError("完了待ちがタイムアウトしました", EXIT.GENERAL)),
        WAIT_TIMEOUT_MS
      );
    });

    // Run the task
    const res = await client.send({ action: "run_task", taskId });
    if (!res.success) {
      throw new CLIError(res.error ?? `タスク '${taskId}' の実行に失敗しました`, EXIT.NOT_FOUND);
    }

    if (!json) {
      console.log(`タスク "${taskId}" を開始しました...`);
    }

    const record = await completionPromise;

    if (json) {
      console.log(JSON.stringify({ success: true, record }));
    } else {
      const status = statusLabel(record.status);
      console.log(`[完了] ${status} (${formatDuration(record)})`);
    }
  } finally {
    client.close();
  }
}

export async function stopTask(taskId: string, json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "stop_task", taskId });
    if (!res.success) {
      throw new CLIError(res.error ?? `タスク '${taskId}' の停止に失敗しました`, EXIT.NOT_FOUND);
    }
    if (json) {
      console.log(JSON.stringify({ success: true }));
    } else {
      console.log(`タスク "${taskId}" を停止しました。`);
    }
  });
}

export async function toggleTask(taskId: string, json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "toggle_task", taskId });
    if (!res.success) {
      throw new CLIError(res.error ?? `タスク '${taskId}' の切り替えに失敗しました`, EXIT.NOT_FOUND);
    }
    if (json) {
      console.log(JSON.stringify({ success: true }));
    } else {
      console.log(`タスク "${taskId}" の有効/無効を切り替えました。`);
    }
  });
}

export async function showLogs(taskId: string | undefined, json: boolean, output: boolean, limit: number) {
  await withClient(async (client) => {
    const res = await client.send({
      action: "get_history",
      taskId,
      limit,
    });
    if (!res.success || !res.history) {
      throw new CLIError(res.error ?? "履歴が返されませんでした", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify(res.history));
      return;
    }

    if (res.history.length === 0) {
      console.log("実行履歴がありません。");
      return;
    }

    if (output) {
      // Show execution output
      for (const r of res.history) {
        console.log(`--- ${r.taskName} (${formatDate(r.startedAt)}) [${statusLabel(r.status)}] ---`);
        if (r.stdout) {
          console.log("[stdout]");
          console.log(r.stdout);
        }
        if (r.stderr) {
          console.log("[stderr]");
          console.log(r.stderr);
        }
        console.log();
      }
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

export async function showStatus(json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "list_tasks" });
    if (!res.success) {
      throw new CLIError(res.error ?? "タスク一覧の取得に失敗しました", EXIT.GENERAL);
    }
    const tasks = res.tasks ?? [];
    const running = tasks.filter((t) => t.isRunning);
    const enabled = tasks.filter((t) => t.task.enabled);

    if (json) {
      console.log(JSON.stringify({
        total: tasks.length,
        enabled: enabled.length,
        running: running.length,
        runningTasks: running.map(t => ({ id: t.task.id, name: t.task.name })),
        nextScheduled: enabled
          .filter(t => t.nextRunAt)
          .sort((a, b) => new Date(a.nextRunAt!).getTime() - new Date(b.nextRunAt!).getTime())
          .slice(0, 5)
          .map(t => ({ id: t.task.id, name: t.task.name, nextRunAt: t.nextRunAt })),
      }));
      return;
    }

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

export async function configGet(json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "get_settings" });
    if (!res.success || !res.settings) {
      throw new CLIError(res.error ?? "設定の取得に失敗しました", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify(res.settings));
      return;
    }

    const s = res.settings;
    console.log(`デフォルトタイムアウト: ${s.default_timeout ?? 3600}秒`);
    console.log(`Slack Bot Token:       ${s.slack_bot_token ? "(設定済み)" : "(未設定)"}`);
    console.log(`Slack Channel:         ${s.slack_channel ?? "(未設定)"}`);
  });
}

export async function configSet(key: string, value: string, json: boolean) {
  const validKeys = ["default_timeout", "slack_bot_token", "slack_channel"];
  if (!validKeys.includes(key)) {
    throw new CLIError(
      `不明な設定キー: ${key} (使用可能: ${validKeys.join(", ")})`,
      EXIT.VALIDATION
    );
  }

  await withClient(async (client) => {
    // 既存の設定を取得してマージ（部分更新で他の値が消えないようにする）
    const getRes = await client.send({ action: "get_settings" });
    const current: GlobalSettings = getRes.settings ?? {};

    switch (key) {
      case "default_timeout":
        current.default_timeout = parsePositiveInt(value, "default_timeout");
        break;
      case "slack_bot_token":
        current.slack_bot_token = value;
        break;
      case "slack_channel":
        current.slack_channel = value;
        break;
    }

    const res = await client.send({ action: "update_settings", settings: current });
    if (!res.success) {
      throw new CLIError(res.error ?? "設定の更新に失敗しました", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify({ success: true }));
    } else {
      console.log(`${key} を ${value} に設定しました。`);
    }
  });
}

export async function syslog(json: boolean, clear: boolean) {
  await withClient(async (client) => {
    if (clear) {
      const res = await client.send({ action: "clear_system_logs" });
      if (!res.success) {
        throw new CLIError(res.error ?? "システムログの削除に失敗しました", EXIT.GENERAL);
      }
      if (json) {
        console.log(JSON.stringify({ success: true }));
      } else {
        console.log("システムログを削除しました。");
      }
      return;
    }

    const res = await client.send({ action: "get_system_logs", limit: 1000 });
    if (!res.success) {
      throw new CLIError(res.error ?? "システムログの取得に失敗しました", EXIT.GENERAL);
    }

    const logs: LogEntry[] = res.systemLogs ?? [];
    if (json) {
      console.log(JSON.stringify({ success: true, systemLogs: logs }));
      return;
    }

    if (logs.length === 0) {
      console.log("ログがありません。");
      return;
    }

    for (const entry of logs) {
      console.log(`${formatTimestamp(entry.timestamp)}  ${entry.tag.padEnd(12)}  ${entry.message}`);
    }
  });
}

export async function reloadTasks(json: boolean) {
  await withClient(async (client) => {
    const res = await client.send({ action: "reload" });
    if (!res.success) {
      throw new CLIError(res.error ?? "再読み込みに失敗しました", EXIT.GENERAL);
    }

    if (json) {
      console.log(JSON.stringify({ success: true }));
    } else {
      console.log("タスク定義を再読み込みしました。");
    }
  });
}
