import { homedir } from "os";
import { join, resolve } from "path";
import { getSocketPath } from "./ipc.ts";

const LABEL = "com.gehnmaisoda.local-runner.daemon";
const PLIST_FILENAME = `${LABEL}.plist`;
const LAUNCH_AGENTS_DIR = join(homedir(), "Library", "LaunchAgents");
const PLIST_PATH = join(LAUNCH_AGENTS_DIR, PLIST_FILENAME);

const isDev = process.env.LOCAL_RUNNER_DEV === "1";
const appName = isDev ? "LocalRunner-Dev" : "LocalRunner";
const LOG_DIR = join(
  homedir(),
  "Library",
  "Application Support",
  appName
);

function findDaemonBinary(): string | null {
  // Look for the daemon binary relative to this project
  const projectRoot = resolve(import.meta.dir, "..", "..");
  const candidates = [
    join(projectRoot, "daemon", ".build", "release", "local-runner"),
    join(projectRoot, "daemon", ".build", "debug", "local-runner"),
  ];
  for (const p of candidates) {
    if (Bun.file(p).size > 0) return p;
  }
  return null;
}

function generatePlist(daemonPath: string): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${daemonPath}</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/daemon.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/daemon.stderr.log</string>
</dict>
</plist>`;
}

export async function install() {
  const daemonPath = findDaemonBinary();
  if (!daemonPath) {
    console.error(
      "デーモンバイナリが見つかりません。先にビルドしてください:\n  cd daemon && swift build -c release"
    );
    process.exit(1);
  }

  // Ensure LaunchAgents directory exists
  await Bun.$`mkdir -p ${LAUNCH_AGENTS_DIR}`.quiet();

  // Ensure log directory exists
  await Bun.$`mkdir -p ${LOG_DIR}`.quiet();

  // Unload if already loaded
  await Bun.$`launchctl unload ${PLIST_PATH} 2>/dev/null`.quiet().nothrow();

  // Write plist
  const plist = generatePlist(daemonPath);
  await Bun.write(PLIST_PATH, plist);

  // Load
  await Bun.$`launchctl load ${PLIST_PATH}`;

  console.log(`デーモンをインストールし、起動しました。`);
  console.log(`  バイナリ: ${daemonPath}`);
  console.log(`  Plist:    ${PLIST_PATH}`);
}

export async function uninstall() {
  const result = await Bun.$`launchctl unload ${PLIST_PATH} 2>/dev/null`
    .quiet()
    .nothrow();

  const file = Bun.file(PLIST_PATH);
  if (await file.exists()) {
    await Bun.$`rm ${PLIST_PATH}`;
  }

  console.log("デーモンをアンインストールしました。");
}

export async function doctor(json = false) {
  type Check = { check: string; ok: boolean; detail: string };
  const checks: Check[] = [];

  if (!json) console.log("=== LocalRunner 診断 ===\n");

  // 1. デーモンバイナリ
  const daemonPath = findDaemonBinary();
  if (daemonPath) {
    checks.push({ check: "daemon_binary", ok: true, detail: daemonPath });
    if (!json) console.log(`[ok] デーモンバイナリ: ${daemonPath}`);
  } else {
    checks.push({ check: "daemon_binary", ok: false, detail: "not found" });
    if (!json) console.log("[!!] デーモンバイナリが見つかりません。実行: cd daemon && swift build -c release");
  }

  // 2. Plist 登録
  const plistExists = await Bun.file(PLIST_PATH).exists();
  if (plistExists) {
    checks.push({ check: "plist", ok: true, detail: PLIST_PATH });
    if (!json) console.log(`[ok] LaunchAgent plist: ${PLIST_PATH}`);
  } else {
    checks.push({ check: "plist", ok: false, detail: "not registered" });
    if (!json) console.log(`[!!] LaunchAgent plist 未登録。実行: lr install`);
  }

  // 3. デーモンプロセス
  const ps = await Bun.$`launchctl list | grep ${LABEL}`.quiet().nothrow();
  const running = ps.exitCode === 0;
  if (running) {
    checks.push({ check: "process", ok: true, detail: "running" });
    if (!json) console.log(`[ok] デーモンプロセス: 実行中`);
  } else {
    checks.push({ check: "process", ok: false, detail: "stopped" });
    if (!json) console.log(`[!!] デーモンプロセス: 停止中`);
  }

  // 4. ソケット
  const socketPath = getSocketPath();
  const socketExists = await Bun.file(socketPath).exists();
  if (socketExists) {
    checks.push({ check: "socket", ok: true, detail: socketPath });
    if (!json) console.log(`[ok] ソケット: ${socketPath}`);
  } else {
    checks.push({ check: "socket", ok: false, detail: socketPath });
    if (!json) console.log(`[!!] ソケットが見つかりません: ${socketPath}`);
  }

  // 5. IPC 接続
  if (socketExists) {
    try {
      const { IPCClient } = await import("./ipc.ts");
      const client = new IPCClient();
      await client.connect();
      const res = await client.send({ action: "list_tasks" });
      client.close();
      if (res.success) {
        const count = res.tasks?.length ?? 0;
        checks.push({ check: "ipc", ok: true, detail: `${count} tasks` });
        if (!json) console.log(`[ok] IPC 接続: 正常 (${count} 件のタスク)`);
      } else {
        checks.push({ check: "ipc", ok: false, detail: res.error ?? "unknown error" });
        if (!json) console.log(`[!!] IPC 接続: エラー - ${res.error}`);
      }
    } catch (e) {
      checks.push({ check: "ipc", ok: false, detail: String(e) });
      if (!json) console.log(`[!!] IPC 接続: 失敗 - ${e}`);
    }
  }

  if (json) {
    const allOk = checks.every(c => c.ok);
    console.log(JSON.stringify({ success: allOk, checks }));
  }
}
