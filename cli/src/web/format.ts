import type { ExecutionRecord, Schedule } from "./types.ts";

const WEEKDAYS = ["日", "月", "火", "水", "木", "金", "土"] as const;

export function formatDate(iso: string | undefined): string {
  if (!iso) return "-";
  const d = new Date(iso);
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  const w = WEEKDAYS[d.getDay()];
  const hh = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  const ss = String(d.getSeconds()).padStart(2, "0");
  return `${mm}/${dd}(${w}) ${hh}:${mi}:${ss}`;
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

// ISO weekday: 1=Mon...7=Sun
const ISO_WEEKDAYS: Record<number, string> = {
  1: "月", 2: "火", 3: "水", 4: "木", 5: "金", 6: "土", 7: "日",
};

export function statusLabel(status: ExecutionRecord["status"]): string {
  switch (status) {
    case "success": return "成功";
    case "failure": return "失敗";
    case "stopped": return "停止";
    case "timeout": return "タイムアウト";
    case "pending": return "保留中";
    case "running": return "実行中";
  }
}

export function formatCountdown(targetMs: number): string {
  const diff = targetMs - Date.now();
  if (diff <= 0) return "まもなく";
  const totalSec = Math.ceil(diff / 1000);
  if (totalSec < 60) return `${totalSec}秒`;
  if (totalSec < 3600) {
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return `${m}分${s}秒`;
  }
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  return `${h}時間${m}分`;
}

export function statusIcon(status: ExecutionRecord["status"]): string {
  switch (status) {
    case "success": return "\u2713"; // ✓
    case "failure": return "\u2717"; // ✗
    case "stopped": return "\u25A0"; // ■
    case "timeout": return "\u23F0"; // ⏰
    case "pending": return "\u23F3"; // ⏳
    default: return "";
  }
}

export function formatSchedule(schedule: Schedule): string {
  switch (schedule.type) {
    case "every_minute": return "毎分";
    case "hourly": return `毎時 :${String(schedule.minute ?? 0).padStart(2, "0")}`;
    case "daily": return `毎日 ${schedule.time ?? "00:00"}`;
    case "weekly": {
      const wds = schedule.weekdays?.length ? schedule.weekdays : [schedule.weekday ?? 1];
      const names = [...wds].sort((a, b) => a - b).map((d) => ISO_WEEKDAYS[d] ?? "月");
      return `毎週${names.join("")} ${schedule.time ?? "00:00"}`;
    }
    case "monthly": {
      const days = schedule.month_days ?? [1];
      const strs = [...days].sort((a, b) => a - b).map((d) => d === -1 ? "末" : `${d}`);
      return `毎月${strs.join("・")}日 ${schedule.time ?? "00:00"}`;
    }
    case "cron": return schedule.expression ?? "cron";
    default: return schedule.type;
  }
}
