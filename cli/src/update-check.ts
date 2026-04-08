const REPO = "gehnmaisoda/local-runner";

export function parseVersion(v: string): number[] {
  return v.replace(/^v/, "").split(".").map(Number);
}

export function isNewer(latest: string, current: string): boolean {
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
    const latestVersion = await fetchLatestVersion();

    if (latestVersion && isNewer(latestVersion, currentVersion)) {
      console.error(
        `\n新しいバージョンがあります: ${currentVersion} → ${latestVersion}\nアップデート: brew upgrade local-runner && lr install`
      );
    }
  } catch {
    // best-effort
  }
}
