import { IPCClient, getSocketPath, type IPCNotification, type IPCRequest, type IPCResponse } from "./ipc.ts";
import { existsSync, statSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";
import index from "./web/index.html";

/** Parse JSON body from request, returning a 400 Response on failure. */
async function parseJsonBody(req: Request): Promise<unknown | Response> {
  try {
    return await req.json();
  } catch {
    return Response.json(
      { error: "不正なJSON形式です。リクエストボディを確認してください。" },
      { status: 400 }
    );
  }
}

// --- IPC connection with auto-reconnect ---

let ipcClient: IPCClient | null = null;
let wsClients = new Set<ServerWebSocket<unknown>>();

type ServerWebSocket<T> = {
  send(data: string | Buffer): void;
  close(): void;
  data: T;
};

async function ensureIPC(): Promise<IPCClient> {
  if (ipcClient?.connected) return ipcClient;
  const wasReconnect = ipcClient !== null;
  const client = new IPCClient();
  try {
    await client.connect();
  } catch (err) {
    ipcClient = null;
    throw err;
  }
  ipcClient = client;
  client.subscribe((notification: IPCNotification) => {
    const msg = JSON.stringify({ type: "notification", ...notification });
    for (const ws of wsClients) {
      ws.send(msg);
    }
  });
  // 再接続時、既存のWSクライアントにリフレッシュを通知
  if (wasReconnect && wsClients.size > 0) {
    const refreshMsg = JSON.stringify({ type: "notification", event: "reconnected" });
    for (const ws of wsClients) {
      ws.send(refreshMsg);
    }
  }
  return client;
}

async function sendToIPC(request: IPCRequest): Promise<IPCResponse> {
  try {
    const client = await ensureIPC();
    return await client.send(request);
  } catch {
    // 接続が切れていた可能性 — リセットして1回リトライ
    ipcClient?.close();
    ipcClient = null;
    const client = await ensureIPC();
    return await client.send(request);
  }
}

// --- API handlers ---

async function handleAPI(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  // ディレクトリ存在チェック（IPC 不要、サーバーが直接確認）
  // ホームディレクトリ配下のみ許可（パストラバーサル対策）
  if (path === "/api/check-dir" && req.method === "GET") {
    const dirPath = url.searchParams.get("path") ?? "";
    if (!dirPath) return Response.json({ exists: false });
    const home = homedir();
    const expanded = resolve(dirPath.replace(/^~/, home));
    if (!expanded.startsWith(home)) {
      return Response.json({ exists: false });
    }
    try {
      const exists = existsSync(expanded) && statSync(expanded).isDirectory();
      return Response.json({ exists });
    } catch {
      return Response.json({ exists: false });
    }
  }

  try {
    if (path === "/api/tasks" && req.method === "GET") {
      const res = await sendToIPC({ action: "list_tasks" });
      return Response.json(res);
    }

    if (path === "/api/history" && req.method === "GET") {
      const taskId = url.searchParams.get("taskId") ?? undefined;
      const limit = parseInt(url.searchParams.get("limit") ?? "50", 10);
      const res = await sendToIPC({ action: "get_history", taskId, limit });
      return Response.json(res);
    }

    if (path.startsWith("/api/tasks/") && req.method === "POST") {
      const taskId = path.split("/")[3];
      const action = path.split("/")[4]; // run, stop, toggle
      if (action === "run") {
        const res = await sendToIPC({ action: "run_task", taskId });
        return Response.json(res);
      }
      if (action === "stop") {
        const res = await sendToIPC({ action: "stop_task", taskId });
        return Response.json(res);
      }
      if (action === "toggle") {
        const res = await sendToIPC({ action: "toggle_task", taskId });
        return Response.json(res);
      }
    }

    if (path === "/api/tasks" && req.method === "POST") {
      const body = await parseJsonBody(req);
      if (body instanceof Response) return body;
      const res = await sendToIPC({ action: "save_task", task: body });
      return Response.json(res);
    }

    if (path.startsWith("/api/tasks/") && req.method === "DELETE") {
      const taskId = path.split("/")[3];
      const res = await sendToIPC({ action: "delete_task", taskId });
      return Response.json(res);
    }

    if (path === "/api/system-logs" && req.method === "GET") {
      const limit = parseInt(url.searchParams.get("limit") ?? "1000", 10);
      const res = await sendToIPC({ action: "get_system_logs", limit });
      return Response.json(res);
    }

    if (path === "/api/system-logs" && req.method === "DELETE") {
      const res = await sendToIPC({ action: "clear_system_logs" });
      return Response.json(res);
    }

    if (path === "/api/settings" && req.method === "GET") {
      const res = await sendToIPC({ action: "get_settings" });
      return Response.json(res);
    }

    if (path === "/api/settings" && req.method === "POST") {
      const body = await parseJsonBody(req);
      if (body instanceof Response) return body;
      const res = await sendToIPC({ action: "update_settings", settings: body });
      return Response.json(res);
    }

    // --- Slack API proxy (CORS 回避) ---
    // トークンは保存済みの設定から取得する（クエリパラメータに露出させない）

    if (path === "/api/slack/channels" && req.method === "GET") {
      const token = await getSlackToken();
      if (!token) return Response.json({ ok: false, error: "slack_bot_token が設定されていません" }, { status: 400 });
      return slackProxy(token, "https://slack.com/api/conversations.list", {
        types: "public_channel",
        exclude_archived: "true",
        limit: "200",
      });
    }

    if (path === "/api/slack/users" && req.method === "GET") {
      const token = await getSlackToken();
      if (!token) return Response.json({ ok: false, error: "slack_bot_token が設定されていません" }, { status: 400 });
      return slackProxy(token, "https://slack.com/api/users.list", { limit: "200" });
    }

    if (path === "/api/slack/test" && req.method === "POST") {
      const body = await parseJsonBody(req);
      if (body instanceof Response) return body;
      const { channel } = body as { channel?: string };
      if (!channel) {
        return Response.json({ ok: false, error: "channel が必要です" }, { status: 400 });
      }
      const token = await getSlackToken();
      if (!token) {
        return Response.json({ ok: false, error: "slack_bot_token が設定されていません" }, { status: 400 });
      }
      return slackProxy(token, "https://slack.com/api/chat.postMessage", {}, {
        channel,
        text: ":white_check_mark: LocalRunner テスト通知\nSlack 連携が正しく設定されています。",
      });
    }

    return Response.json({ error: "見つかりません" }, { status: 404 });
  } catch (err) {
    return Response.json(
      { error: `デーモンへの接続に失敗: ${err}` },
      { status: 502 }
    );
  }
}

// --- Port conflict detection ---

/** Check whether a LocalRunner instance is already listening at the given URL. */
async function isLocalRunnerAt(url: string): Promise<boolean> {
  try {
    const res = await fetch(`${url}/api/tasks`, { signal: AbortSignal.timeout(1000) });
    if (!res.ok && res.status !== 502) return false;
    const body = await res.json();
    // Our API returns { tasks: [...] } or { error: "..." } with status 502 when daemon is down
    return Array.isArray(body.tasks) || (res.status === 502 && typeof body.error === "string");
  } catch {
    return false;
  }
}

// --- Server ---

const DEFAULT_PORT = 4510;

export async function startServer(preferredPort?: number) {
  const port = preferredPort ?? DEFAULT_PORT;

  // Try to connect to daemon first
  try {
    await ensureIPC();
  } catch {
    console.warn("警告: デーモンに接続できませんでした。リクエスト時に再接続を試みます。");
  }

  let server;
  try {
    server = Bun.serve({
      port,
      routes: {
        "/": index,
      },
      async fetch(req, server) {
        const url = new URL(req.url);

        // WebSocket upgrade
        if (url.pathname === "/ws") {
          if (server.upgrade(req)) return;
          return new Response("WebSocket アップグレードに失敗しました", { status: 400 });
        }

        // API routes
        if (url.pathname.startsWith("/api/")) {
          return handleAPI(req);
        }

        return new Response("見つかりません", { status: 404 });
      },
      websocket: {
        open(ws) {
          wsClients.add(ws as any);
        },
        message() {},
        close(ws) {
          wsClients.delete(ws as any);
        },
      },
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    const code = (err as NodeJS.ErrnoException)?.code;
    if (code === "EADDRINUSE" || msg.includes("EADDRINUSE") || msg.includes("address already in use")) {
      const url = `http://localhost:${port}`;
      if (await isLocalRunnerAt(url)) {
        console.log(`LocalRunner は既に起動しています: ${url}`);
      } else {
        console.error(`エラー: ポート ${port} は既に使用されています。`);
        console.error(`別のポートを指定してください: lr --port <ポート番号>`);
      }
      process.exit(1);
    }
    throw err;
  }

  const actualPort = server.port;
  const url = `http://localhost:${actualPort}`;
  console.log(`LocalRunner Web UI: ${url}`);

  // Open browser
  Bun.spawn(["open", url], { stdout: "ignore", stderr: "ignore" });

  return server;
}

// --- Slack API helpers ---

/** 保存済みの設定から Slack Bot Token を取得する。 */
async function getSlackToken(): Promise<string | null> {
  try {
    const res = await sendToIPC({ action: "get_settings" });
    return res.settings?.slack_bot_token || null;
  } catch {
    return null;
  }
}

/** Slack API をプロキシする。GET の場合は params をクエリ文字列に、jsonBody がある場合は POST で送信。 */
async function slackProxy(
  token: string,
  apiUrl: string,
  params: Record<string, string>,
  jsonBody?: Record<string, unknown>,
): Promise<Response> {
  try {
    const qs = new URLSearchParams(params).toString();
    const url = qs ? `${apiUrl}?${qs}` : apiUrl;
    const options: RequestInit = {
      headers: { Authorization: `Bearer ${token}` },
    };
    if (jsonBody) {
      options.method = "POST";
      options.headers = {
        ...options.headers,
        "Content-Type": "application/json; charset=utf-8",
      };
      options.body = JSON.stringify(jsonBody);
    }
    const res = await fetch(url, options);
    return Response.json(await res.json());
  } catch (err) {
    return Response.json(
      { ok: false, error: `Slack API への接続に失敗: ${err}` },
      { status: 502 },
    );
  }
}
