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
      "Daemon binary not found. Build it first:\n  cd daemon && swift build -c release"
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

  console.log(`Daemon installed and started.`);
  console.log(`  Binary: ${daemonPath}`);
  console.log(`  Plist:  ${PLIST_PATH}`);
}

export async function uninstall() {
  const result = await Bun.$`launchctl unload ${PLIST_PATH} 2>/dev/null`
    .quiet()
    .nothrow();

  const file = Bun.file(PLIST_PATH);
  if (await file.exists()) {
    await Bun.$`rm ${PLIST_PATH}`;
  }

  console.log("Daemon uninstalled.");
}

export async function doctor() {
  console.log("=== LocalRunner Doctor ===\n");

  // 1. Daemon binary
  const daemonPath = findDaemonBinary();
  if (daemonPath) {
    console.log(`[ok] Daemon binary: ${daemonPath}`);
  } else {
    console.log("[!!] Daemon binary not found. Run: cd daemon && swift build -c release");
  }

  // 2. Plist installed
  const plistExists = await Bun.file(PLIST_PATH).exists();
  if (plistExists) {
    console.log(`[ok] LaunchAgent plist: ${PLIST_PATH}`);
  } else {
    console.log(`[!!] LaunchAgent plist not installed. Run: lr install`);
  }

  // 3. Daemon process running
  const ps = await Bun.$`launchctl list | grep ${LABEL}`.quiet().nothrow();
  const running = ps.exitCode === 0;
  if (running) {
    console.log(`[ok] Daemon process: running`);
  } else {
    console.log(`[!!] Daemon process: not running`);
  }

  // 4. Socket exists
  const socketPath = getSocketPath();
  const socketExists = await Bun.file(socketPath).exists();
  if (socketExists) {
    console.log(`[ok] Socket: ${socketPath}`);
  } else {
    console.log(`[!!] Socket not found: ${socketPath}`);
  }

  // 5. IPC connection
  if (socketExists) {
    try {
      const { IPCClient } = await import("./ipc.ts");
      const client = new IPCClient();
      await client.connect();
      const res = await client.send({ action: "list_tasks" });
      client.close();
      if (res.success) {
        console.log(`[ok] IPC connection: working (${res.tasks?.length ?? 0} tasks)`);
      } else {
        console.log(`[!!] IPC connection: error - ${res.error}`);
      }
    } catch (e) {
      console.log(`[!!] IPC connection: failed - ${e}`);
    }
  }
}
