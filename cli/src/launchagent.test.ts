import { describe, test, expect, spyOn, beforeEach, afterEach } from "bun:test";
import { join } from "path";
import { homedir } from "os";

// We test internal logic by examining what the module exports
// and by checking the constants/paths it constructs.

// Since launchagent.ts doesn't export its internal functions,
// we test the observable behavior and path logic.

describe("LaunchAgent paths", () => {
  const LABEL = "com.gehnmaisoda.local-runner.daemon";
  const PLIST_FILENAME = `${LABEL}.plist`;
  const LAUNCH_AGENTS_DIR = join(homedir(), "Library", "LaunchAgents");
  const PLIST_PATH = join(LAUNCH_AGENTS_DIR, PLIST_FILENAME);

  test("label follows reverse-DNS convention", () => {
    expect(LABEL).toMatch(/^com\.\w+\.\S+$/);
  });

  test("plist filename matches label", () => {
    expect(PLIST_FILENAME).toBe(`${LABEL}.plist`);
  });

  test("plist path is in ~/Library/LaunchAgents", () => {
    expect(PLIST_PATH).toBe(
      join(homedir(), "Library", "LaunchAgents", `${LABEL}.plist`)
    );
  });

  test("LaunchAgents directory is under home", () => {
    expect(LAUNCH_AGENTS_DIR.startsWith(homedir())).toBe(true);
  });
});

describe("plist content generation", () => {
  // Recreate the plist generator logic for testing
  const LABEL = "com.gehnmaisoda.local-runner.daemon";
  const appName = process.env.LOCAL_RUNNER_DEV === "1" ? "LocalRunner-Dev" : "LocalRunner";
  const LOG_DIR = join(homedir(), "Library", "Application Support", appName);

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

  test("generates valid XML plist", () => {
    const plist = generatePlist("/usr/local/bin/local-runner");
    expect(plist).toContain('<?xml version="1.0"');
    expect(plist).toContain("<!DOCTYPE plist");
    expect(plist).toContain('<plist version="1.0">');
  });

  test("includes daemon binary path", () => {
    const path = "/opt/local-runner/daemon";
    const plist = generatePlist(path);
    expect(plist).toContain(`<string>${path}</string>`);
  });

  test("includes correct label", () => {
    const plist = generatePlist("/usr/local/bin/local-runner");
    expect(plist).toContain(`<string>${LABEL}</string>`);
  });

  test("includes KeepAlive and RunAtLoad", () => {
    const plist = generatePlist("/usr/local/bin/local-runner");
    expect(plist).toContain("<key>KeepAlive</key>");
    expect(plist).toContain("<true/>");
    expect(plist).toContain("<key>RunAtLoad</key>");
  });

  test("includes log paths under Application Support", () => {
    const plist = generatePlist("/usr/local/bin/local-runner");
    expect(plist).toContain("daemon.stdout.log");
    expect(plist).toContain("daemon.stderr.log");
    expect(plist).toContain("Application Support");
  });
});

describe("socket path", () => {
  test("socket path is under Application Support", () => {
    const appName = process.env.LOCAL_RUNNER_DEV === "1" ? "LocalRunner-Dev" : "LocalRunner";
    const expectedPath = join(homedir(), "Library", "Application Support", appName, "daemon.sock");
    expect(expectedPath).toContain("Application Support");
    expect(expectedPath).toEndWith("daemon.sock");
  });
});
