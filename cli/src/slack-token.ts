/**
 * 設定から Slack Bot Token を決める。
 *
 * `slack_bot_token` に直接書かれていればそれを使い、空なら `slack_bot_token_command` を実行して
 * 標準出力を使う。デーモン側の SlackTokenResolver と同じ規則。
 */
import type { GlobalSettings } from "./ipc.ts";

/** コマンドの実行を待つ上限。応答しないコマンドで Web UI を止め続けない。 */
export const TOKEN_COMMAND_TIMEOUT_MS = 20_000;

type TokenSettings = Pick<GlobalSettings, "slack_bot_token" | "slack_bot_token_command">;
type CommandRunner = (command: string) => Promise<string | null>;

/** 直接指定かコマンドのどちらかが設定されているか。 */
export function hasSlackToken(settings: TokenSettings | null | undefined): boolean {
  return !!(settings?.slack_bot_token?.trim() || settings?.slack_bot_token_command?.trim());
}

/** Bot Token を返す。取得できなければ null。 */
export async function resolveSlackToken(
  settings: TokenSettings | null | undefined,
  run: CommandRunner = runTokenCommand,
): Promise<string | null> {
  const direct = settings?.slack_bot_token?.trim();
  if (direct) return direct;
  const command = settings?.slack_bot_token_command?.trim();
  if (!command) return null;
  return (await run(command))?.trim() || null;
}

/** コマンドをログインシェルで実行し、標準出力を返す。失敗・タイムアウト時は null。 */
export async function runTokenCommand(
  command: string,
  timeoutMs: number = TOKEN_COMMAND_TIMEOUT_MS,
): Promise<string | null> {
  try {
    const proc = Bun.spawn(["/bin/zsh", "-l", "-c", command], {
      stdin: "ignore",
      stdout: "pipe",
      stderr: "ignore",
    });
    const timer = setTimeout(() => proc.kill(), timeoutMs);
    try {
      const [output, exitCode] = await Promise.all([new Response(proc.stdout).text(), proc.exited]);
      return exitCode === 0 ? output : null;
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return null;
  }
}
