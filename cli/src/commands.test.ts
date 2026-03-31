import { describe, test, expect } from "bun:test";
import { formatDate, formatDuration, statusIcon, pad } from "./commands.ts";

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
