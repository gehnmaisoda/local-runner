import { describe, test, expect } from "bun:test";
import {
  formatDate, formatDuration, formatTimestamp, statusIcon, pad,
  formatSchedule, generateId, buildSchedule, applyScheduleEdits,
  statusLabel, parsePositiveInt,
  CLIError, EXIT,
} from "./commands.ts";

// --- Existing formatter tests ---

describe("formatDate", () => {
  test("returns '-' for undefined", () => {
    expect(formatDate(undefined)).toBe("-");
  });

  test("formats ISO date string", () => {
    const result = formatDate("2026-03-31T09:30:15Z");
    expect(result).toBeTruthy();
    expect(result).not.toBe("-");
  });
});

describe("formatDuration", () => {
  test("returns '-' when finishedAt is missing", () => {
    expect(formatDuration({ startedAt: "2026-03-31T09:00:00Z", status: "running" } as any)).toBe("-");
  });

  test("formats milliseconds", () => {
    expect(formatDuration({
      startedAt: "2026-03-31T09:00:00.000Z",
      finishedAt: "2026-03-31T09:00:00.500Z",
      status: "success",
    } as any)).toBe("500ms");
  });

  test("formats seconds", () => {
    expect(formatDuration({
      startedAt: "2026-03-31T09:00:00Z",
      finishedAt: "2026-03-31T09:00:05Z",
      status: "success",
    } as any)).toBe("5.0s");
  });

  test("formats minutes and seconds", () => {
    expect(formatDuration({
      startedAt: "2026-03-31T09:00:00Z",
      finishedAt: "2026-03-31T09:02:30Z",
      status: "success",
    } as any)).toBe("2m30s");
  });
});

describe("statusIcon", () => {
  test("returns play icon for running task", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: true },
      isRunning: true,
    } as any)).toBe("\u25B6");
  });

  test("returns circle for disabled task", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: false },
      isRunning: false,
    } as any)).toBe("\u25CB");
  });

  test("returns X for failed task", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: true },
      isRunning: false,
      lastRun: { startedAt: "", finishedAt: "", status: "failure" },
    } as any)).toBe("\u2717");
  });

  test("returns clock for timeout", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: true },
      isRunning: false,
      lastRun: { startedAt: "", finishedAt: "", status: "timeout" },
    } as any)).toBe("\u23F0");
  });

  test("returns check for success", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: true },
      isRunning: false,
      lastRun: { startedAt: "", finishedAt: "", status: "success" },
    } as any)).toBe("\u2713");
  });

  test("returns circle when no history", () => {
    expect(statusIcon({
      task: { id: "t1", name: "Test", enabled: true },
      isRunning: false,
    } as any)).toBe("\u25CB");
  });
});

describe("pad", () => {
  test("pads short strings", () => {
    expect(pad("hi", 5)).toBe("hi   ");
  });

  test("truncates long strings", () => {
    expect(pad("hello world", 5)).toBe("hello");
  });

  test("returns exact length strings as-is", () => {
    expect(pad("hello", 5)).toBe("hello");
  });

  test("handles empty string", () => {
    expect(pad("", 3)).toBe("   ");
  });
});

// --- New formatter tests ---

describe("formatSchedule", () => {
  test("formats every_minute", () => {
    expect(formatSchedule({ type: "every_minute" })).toBe("毎分");
  });

  test("formats hourly with default minute", () => {
    expect(formatSchedule({ type: "hourly" })).toBe("毎時 0分");
  });

  test("formats hourly with specified minute", () => {
    expect(formatSchedule({ type: "hourly", minute: 30 })).toBe("毎時 30分");
  });

  test("formats daily with time", () => {
    expect(formatSchedule({ type: "daily", time: "03:00" })).toBe("毎日 03:00");
  });

  test("formats daily with default time", () => {
    expect(formatSchedule({ type: "daily" })).toBe("毎日 00:00");
  });

  test("formats weekly with single weekday (legacy)", () => {
    expect(formatSchedule({ type: "weekly", weekday: 1, time: "09:00" })).toBe("毎週 月曜 09:00");
  });

  test("formats weekly with multiple weekdays", () => {
    expect(formatSchedule({ type: "weekly", weekdays: [1, 3, 5], time: "09:00" })).toBe("毎週 月,水,金曜 09:00");
  });

  test("formats weekly with Sunday", () => {
    expect(formatSchedule({ type: "weekly", weekdays: [7], time: "10:00" })).toBe("毎週 日曜 10:00");
  });

  test("formats monthly with days", () => {
    expect(formatSchedule({ type: "monthly", month_days: [1, 15], time: "00:00" })).toBe("毎月 1日,15日 00:00");
  });

  test("formats monthly with last day", () => {
    expect(formatSchedule({ type: "monthly", month_days: [-1], time: "23:00" })).toBe("毎月 末日 23:00");
  });

  test("formats cron expression", () => {
    expect(formatSchedule({ type: "cron", expression: "*/5 * * * *" })).toBe("cron: */5 * * * *");
  });

  test("handles unknown type", () => {
    expect(formatSchedule({ type: "custom" })).toBe("custom");
  });
});

describe("generateId", () => {
  test("generates slug from ASCII name", () => {
    expect(generateId("My Backup Task")).toBe("my-backup-task");
  });

  test("generates timestamp ID for non-ASCII names", () => {
    const id = generateId("毎日バックアップ");
    expect(id).toMatch(/^task-\d+$/);
  });

  test("removes special characters", () => {
    expect(generateId("test!@#task")).toBe("testtask");
  });

  test("collapses multiple hyphens", () => {
    expect(generateId("test  --  task")).toBe("test-task");
  });

  test("truncates to 50 characters", () => {
    const longName = "a".repeat(60);
    expect(generateId(longName).length).toBeLessThanOrEqual(50);
  });

  test("handles empty string", () => {
    const id = generateId("");
    expect(id).toMatch(/^task-\d+$/);
  });
});

// --- buildSchedule tests ---

describe("buildSchedule", () => {
  test("builds every_minute schedule", () => {
    const opts = new Map([["schedule-type", "every_minute"]]);
    expect(buildSchedule(opts)).toEqual({ type: "every_minute" });
  });

  test("builds hourly schedule with default minute", () => {
    const opts = new Map([["schedule-type", "hourly"]]);
    expect(buildSchedule(opts)).toEqual({ type: "hourly", minute: 0 });
  });

  test("builds hourly schedule with specified minute", () => {
    const opts = new Map([["schedule-type", "hourly"], ["minute", "30"]]);
    expect(buildSchedule(opts)).toEqual({ type: "hourly", minute: 30 });
  });

  test("builds daily schedule", () => {
    const opts = new Map([["schedule-type", "daily"], ["time", "09:00"]]);
    expect(buildSchedule(opts)).toEqual({ type: "daily", time: "09:00" });
  });

  test("builds weekly schedule with weekdays", () => {
    const opts = new Map([["schedule-type", "weekly"], ["weekdays", "1,3,5"], ["time", "10:00"]]);
    expect(buildSchedule(opts)).toEqual({ type: "weekly", time: "10:00", weekdays: [1, 3, 5] });
  });

  test("builds weekly schedule with default weekday", () => {
    const opts = new Map([["schedule-type", "weekly"]]);
    expect(buildSchedule(opts)).toEqual({ type: "weekly", time: "00:00", weekdays: [1] });
  });

  test("builds monthly schedule with month-days", () => {
    const opts = new Map([["schedule-type", "monthly"], ["month-days", "1,15,-1"], ["time", "03:00"]]);
    expect(buildSchedule(opts)).toEqual({ type: "monthly", time: "03:00", month_days: [1, 15, -1] });
  });

  test("builds cron schedule", () => {
    const opts = new Map([["schedule-type", "cron"], ["cron", "*/5 * * * *"]]);
    expect(buildSchedule(opts)).toEqual({ type: "cron", expression: "*/5 * * * *" });
  });

  test("throws when schedule-type is missing", () => {
    expect(() => buildSchedule(new Map())).toThrow(CLIError);
    try { buildSchedule(new Map()); } catch (e: any) {
      expect(e.exitCode).toBe(EXIT.VALIDATION);
    }
  });

  test("throws for invalid schedule type", () => {
    const opts = new Map([["schedule-type", "invalid"]]);
    expect(() => buildSchedule(opts)).toThrow(CLIError);
  });

  test("throws when cron type has no expression", () => {
    const opts = new Map([["schedule-type", "cron"]]);
    expect(() => buildSchedule(opts)).toThrow(CLIError);
  });

  test("throws for invalid hourly minute", () => {
    const opts = new Map([["schedule-type", "hourly"], ["minute", "60"]]);
    expect(() => buildSchedule(opts)).toThrow(CLIError);
  });

  test("throws for negative hourly minute", () => {
    const opts = new Map([["schedule-type", "hourly"], ["minute", "-1"]]);
    expect(() => buildSchedule(opts)).toThrow(CLIError);
  });

  test("throws for non-numeric hourly minute", () => {
    const opts = new Map([["schedule-type", "hourly"], ["minute", "abc"]]);
    expect(() => buildSchedule(opts)).toThrow(CLIError);
  });
});

// --- applyScheduleEdits tests ---

describe("applyScheduleEdits", () => {
  test("rebuilds schedule when schedule-type changes", () => {
    const existing = { type: "daily", time: "09:00" };
    const opts = new Map([["schedule-type", "hourly"], ["minute", "15"]]);
    expect(applyScheduleEdits(existing, opts)).toEqual({ type: "hourly", minute: 15 });
  });

  test("updates time without changing type", () => {
    const existing = { type: "daily", time: "09:00" };
    const opts = new Map([["time", "15:00"]]);
    const result = applyScheduleEdits(existing, opts);
    expect(result.type).toBe("daily");
    expect(result.time).toBe("15:00");
  });

  test("updates weekdays without changing type", () => {
    const existing = { type: "weekly", weekdays: [1], time: "09:00" };
    const opts = new Map([["weekdays", "1,3,5"]]);
    const result = applyScheduleEdits(existing, opts);
    expect(result.weekdays).toEqual([1, 3, 5]);
    expect(result.time).toBe("09:00");
  });

  test("updates month-days without changing type", () => {
    const existing = { type: "monthly", month_days: [1], time: "00:00" };
    const opts = new Map([["month-days", "1,15,-1"]]);
    const result = applyScheduleEdits(existing, opts);
    expect(result.month_days).toEqual([1, 15, -1]);
  });

  test("updates cron expression without changing type", () => {
    const existing = { type: "cron", expression: "0 * * * *" };
    const opts = new Map([["cron", "*/5 * * * *"]]);
    const result = applyScheduleEdits(existing, opts);
    expect(result.expression).toBe("*/5 * * * *");
  });

  test("updates minute without changing type", () => {
    const existing = { type: "hourly", minute: 0 };
    const opts = new Map([["minute", "30"]]);
    const result = applyScheduleEdits(existing, opts);
    expect(result.minute).toBe(30);
  });

  test("returns existing when no options provided", () => {
    const existing = { type: "daily", time: "09:00" };
    const result = applyScheduleEdits(existing, new Map());
    expect(result).toEqual(existing);
  });
});

// --- formatTimestamp tests ---

describe("formatTimestamp", () => {
  test("formats ISO date to YYYY-MM-DD HH:mm:ss", () => {
    // Use a fixed UTC date and check the local representation
    const result = formatTimestamp("2026-01-05T00:09:03Z");
    // Should contain the date part with zero-padded values
    expect(result).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });

  test("zero-pads single digit month and day", () => {
    // Use a Date known in local timezone to verify zero-padding
    const d = new Date(2026, 0, 5, 3, 7, 9); // Jan 5, 03:07:09 local
    const result = formatTimestamp(d.toISOString());
    expect(result).toBe("2026-01-05 03:07:09");
  });
});

// --- statusLabel tests ---

describe("statusLabel", () => {
  test("returns Japanese labels for all statuses", () => {
    expect(statusLabel("success")).toBe("成功");
    expect(statusLabel("failure")).toBe("失敗");
    expect(statusLabel("timeout")).toBe("タイムアウト");
    expect(statusLabel("running")).toBe("実行中");
    expect(statusLabel("stopped")).toBe("停止");
  });

  test("returns raw string for unknown status", () => {
    expect(statusLabel("pending")).toBe("pending");
  });
});

// --- parsePositiveInt tests ---

describe("parsePositiveInt", () => {
  test("parses valid positive integers", () => {
    expect(parsePositiveInt("42", "test")).toBe(42);
    expect(parsePositiveInt("1", "test")).toBe(1);
  });

  test("throws for zero", () => {
    expect(() => parsePositiveInt("0", "--timeout")).toThrow(CLIError);
  });

  test("throws for negative number", () => {
    expect(() => parsePositiveInt("-5", "--timeout")).toThrow(CLIError);
  });

  test("throws for non-numeric string", () => {
    expect(() => parsePositiveInt("abc", "--limit")).toThrow(CLIError);
  });

  test("throws with correct exit code", () => {
    try { parsePositiveInt("abc", "--timeout"); } catch (e: any) {
      expect(e.exitCode).toBe(EXIT.VALIDATION);
    }
  });

  test("includes label in error message", () => {
    try { parsePositiveInt("abc", "--timeout"); } catch (e: any) {
      expect(e.message).toContain("--timeout");
    }
  });
});

// --- CLIError tests ---

describe("CLIError", () => {
  test("has default exit code 1", () => {
    const err = new CLIError("test");
    expect(err.exitCode).toBe(EXIT.GENERAL);
    expect(err.message).toBe("test");
  });

  test("accepts custom exit code", () => {
    const err = new CLIError("not found", EXIT.NOT_FOUND);
    expect(err.exitCode).toBe(2);
  });

  test("is instance of Error", () => {
    expect(new CLIError("test")).toBeInstanceOf(Error);
  });
});
