import { describe, expect, test } from "bun:test";
import { hasSlackToken, resolveSlackToken, runTokenCommand } from "./slack-token.ts";

describe("resolveSlackToken", () => {
  test("direct token wins over the command", async () => {
    const token = await resolveSlackToken(
      { slack_bot_token: "xoxb-direct", slack_bot_token_command: "ignored" },
      async () => "xoxb-from-command",
    );
    expect(token).toBe("xoxb-direct");
  });

  test("command output is used when the direct token is empty", async () => {
    const seen: string[] = [];
    const token = await resolveSlackToken({ slack_bot_token: "", slack_bot_token_command: "get-token" }, async (command) => {
      seen.push(command);
      return "xoxb-from-command\n";
    });
    expect(seen).toEqual(["get-token"]);
    expect(token).toBe("xoxb-from-command");
  });

  test("returns null when nothing is configured or the command fails", async () => {
    expect(await resolveSlackToken({}, async () => "unused")).toBeNull();
    expect(await resolveSlackToken(null)).toBeNull();
    expect(await resolveSlackToken({ slack_bot_token_command: "get-token" }, async () => null)).toBeNull();
    expect(await resolveSlackToken({ slack_bot_token_command: "get-token" }, async () => "\n")).toBeNull();
  });
});

describe("hasSlackToken", () => {
  test("is true for either a direct token or a command", () => {
    expect(hasSlackToken({ slack_bot_token: "xoxb-x" })).toBe(true);
    expect(hasSlackToken({ slack_bot_token_command: "get-token" })).toBe(true);
    expect(hasSlackToken({ slack_bot_token: " ", slack_bot_token_command: "" })).toBe(false);
    expect(hasSlackToken(undefined)).toBe(false);
  });
});

describe("runTokenCommand", () => {
  test("returns stdout of a successful command", async () => {
    expect(await runTokenCommand("printf xoxb-shell")).toBe("xoxb-shell");
  });

  test("returns null on non-zero exit", async () => {
    expect(await runTokenCommand("echo nope; exit 3")).toBeNull();
  });

  test("gives up after the timeout", async () => {
    const started = Date.now();
    expect(await runTokenCommand("exec sleep 5", 300)).toBeNull();
    expect(Date.now() - started).toBeLessThan(4000);
  });
});
