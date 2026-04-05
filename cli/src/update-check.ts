import { homedir } from "os";
import { join } from "path";

const isDev = process.env.LOCAL_RUNNER_DEV === "1";
const appName = isDev ? "LocalRunner-Dev" : "LocalRunner";
const CACHE_PATH = join(homedir(), "Library", "Application Support", appName, "update-check.json");
const CHECK_INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours
const REPO = "gehnmaisoda/local-runner";

interface CacheData {
  lastChecked: number;
  latestVersion: string;
}

function parseVersion(v: string): number[] {
  return v.replace(/^v/, "").split(".").map(Number);
}

function isNewer(latest: string, current: string): boolean {
  const l = parseVersion(latest);
  const c = parseVersion(current);
  for (let i = 0; i < Math.max(l.length, c.length); i++) {
    const lv = l[i] ?? 0;
    const cv = c[i] ?? 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

async function readCache(): Promise<CacheData | null> {
  try {
    const file = Bun.file(CACHE_PATH);
    if (!(await file.exists())) return null;
    return await file.json();
  } catch {
    return null;
  }
}

async function writeCache(data: CacheData): Promise<void> {
  try {
    await Bun.write(CACHE_PATH, JSON.stringify(data));
  } catch {
    // best-effort
  }
}

async function fetchLatestVersion(): Promise<string | null> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: "application/vnd.github.v3+json" },
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data.tag_name?.replace(/^v/, "") ?? null;
  } catch {
    return null;
  }
}

/**
 * 新バージョンがあれば通知メッセージを stderr に表示する。
 * ベストエフォート。失敗しても例外を投げない。
 */
export async function checkForUpdates(currentVersion: string): Promise<void> {
  try {
    const cache = await readCache();
    const now = Date.now();

    let latestVersion: string | null = null;

    if (cache && now - cache.lastChecked < CHECK_INTERVAL_MS) {
      latestVersion = cache.latestVersion;
    } else {
      latestVersion = await fetchLatestVersion();
      if (latestVersion) {
        await writeCache({ lastChecked: now, latestVersion });
      }
    }

    if (latestVersion && isNewer(latestVersion, currentVersion)) {
      console.error(
        `\n新しいバージョンがあります: ${currentVersion} → ${latestVersion}\nアップデート: brew upgrade local-runner && lr install`
      );
    }
  } catch {
    // best-effort
  }
}
