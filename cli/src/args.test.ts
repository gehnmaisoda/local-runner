import { describe, test, expect } from "bun:test";
import { parseArgs } from "./args.ts";

describe("parseArgs", () => {
  test("parses positional arguments", () => {
    const result = parseArgs(["list"]);
    expect(result.positionals).toEqual(["list"]);
    expect(result.flags.size).toBe(0);
    expect(result.options.size).toBe(0);
  });

  test("parses multiple positional arguments", () => {
    const result = parseArgs(["config", "set", "default_timeout", "1800"]);
    expect(result.positionals).toEqual(["config", "set", "default_timeout", "1800"]);
  });

  test("parses boolean flags", () => {
    const result = parseArgs(["list", "--json"]);
    expect(result.positionals).toEqual(["list"]);
    expect(result.flags.has("json")).toBe(true);
  });

  test("parses multiple boolean flags", () => {
    const result = parseArgs(["run", "backup", "--wait", "--json"]);
    expect(result.positionals).toEqual(["run", "backup"]);
    expect(result.flags.has("wait")).toBe(true);
    expect(result.flags.has("json")).toBe(true);
  });

  test("parses key-value options", () => {
    const result = parseArgs(["create", "--name", "test", "--command", "echo hi"]);
    expect(result.positionals).toEqual(["create"]);
    expect(result.options.get("name")).toBe("test");
    expect(result.options.get("command")).toBe("echo hi");
  });

  test("parses short flags", () => {
    const result = parseArgs(["delete", "backup", "-y"]);
    expect(result.flags.has("yes")).toBe(true);
  });

  test("parses -h as help", () => {
    const result = parseArgs(["-h"]);
    expect(result.flags.has("help")).toBe(true);
  });

  test("parses -n as limit option", () => {
    const result = parseArgs(["logs", "-n", "10"]);
    expect(result.options.get("limit")).toBe("10");
  });

  test("parses --no-catch-up as boolean flag", () => {
    const result = parseArgs(["create", "--no-catch-up"]);
    expect(result.flags.has("no-catch-up")).toBe(true);
  });

  test("parses --catch-up as boolean flag", () => {
    const result = parseArgs(["create", "--catch-up"]);
    expect(result.flags.has("catch-up")).toBe(true);
  });

  test("parses --notify and --no-notify", () => {
    const result1 = parseArgs(["edit", "t1", "--notify"]);
    expect(result1.flags.has("notify")).toBe(true);

    const result2 = parseArgs(["edit", "t1", "--no-notify"]);
    expect(result2.flags.has("no-notify")).toBe(true);
  });

  test("parses --disabled flag", () => {
    const result = parseArgs(["create", "--disabled"]);
    expect(result.flags.has("disabled")).toBe(true);
  });

  test("parses --output flag", () => {
    const result = parseArgs(["logs", "backup", "--output"]);
    expect(result.flags.has("output")).toBe(true);
  });

  test("stops parsing after --", () => {
    const result = parseArgs(["create", "--", "--name", "test"]);
    expect(result.positionals).toEqual(["create", "--name", "test"]);
    expect(result.options.size).toBe(0);
  });

  test("handles mixed positionals, flags, and options", () => {
    const result = parseArgs([
      "create",
      "--name", "backup",
      "--command", "rsync",
      "--schedule-type", "daily",
      "--time", "03:00",
      "--catch-up",
      "--json",
      "--timeout", "600",
    ]);
    expect(result.positionals).toEqual(["create"]);
    expect(result.options.get("name")).toBe("backup");
    expect(result.options.get("command")).toBe("rsync");
    expect(result.options.get("schedule-type")).toBe("daily");
    expect(result.options.get("time")).toBe("03:00");
    expect(result.options.get("timeout")).toBe("600");
    expect(result.flags.has("catch-up")).toBe(true);
    expect(result.flags.has("json")).toBe(true);
  });

  test("parses --last as option", () => {
    const result = parseArgs(["logs", "--last", "5"]);
    expect(result.options.get("last")).toBe("5");
  });

  test("returns empty for no arguments", () => {
    const result = parseArgs([]);
    expect(result.positionals).toEqual([]);
    expect(result.flags.size).toBe(0);
    expect(result.options.size).toBe(0);
  });

  test("ignores option at end with no value", () => {
    const result = parseArgs(["create", "--name"]);
    expect(result.positionals).toEqual(["create"]);
    expect(result.options.has("name")).toBe(false);
  });

  test("parses --version flag", () => {
    const result = parseArgs(["--version"]);
    expect(result.flags.has("version")).toBe(true);
  });

  test("parses -V as version", () => {
    const result = parseArgs(["-V"]);
    expect(result.flags.has("version")).toBe(true);
  });

  test("parses -v as version", () => {
    const result = parseArgs(["-v"]);
    expect(result.flags.has("version")).toBe(true);
  });

  test("does not consume flag as option value", () => {
    // --name is a value-taking option, but if next arg is missing, it's skipped
    const result = parseArgs(["--timeout"]);
    expect(result.options.has("timeout")).toBe(false);
  });

  test("handles -n at end with no value", () => {
    const result = parseArgs(["logs", "-n"]);
    expect(result.options.has("limit")).toBe(false);
  });
});
