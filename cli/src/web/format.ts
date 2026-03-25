import type { ExecutionRecord, Schedule } from "./types.ts";

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

// ISO weekday: 1=Mon...7=Sun
const ISO_WEEKDAYS: Record<number, string> = {
  1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun",
};

export function formatSchedule(schedule: Schedule): string {
  switch (schedule.type) {
    case "every_minute": return "Every minute";
    case "hourly": return `Hourly at :${String(schedule.minute ?? 0).padStart(2, "0")}`;
    case "daily": return `Daily at ${schedule.time ?? "00:00"}`;
    case "weekly": return `${ISO_WEEKDAYS[schedule.weekday ?? 1] ?? "Mon"} ${schedule.time ?? "00:00"}`;
    case "cron": return schedule.expression ?? "cron";
    default: return schedule.type;
  }
}
