import { IPCClient, getSocketPath, type IPCNotification, type IPCRequest, type IPCResponse } from "./ipc.ts";
import { existsSync, statSync } from "fs";
import { homedir } from "os";
import { resolve } from "path";
import index from "./web/index.html";

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
      const body = await req.json();
      const res = await sendToIPC({ action: "save_task", task: body });
      return Response.json(res);
    }

    if (path.startsWith("/api/tasks/") && req.method === "DELETE") {
      const taskId = path.split("/")[3];
      const res = await sendToIPC({ action: "delete_task", taskId });
      return Response.json(res);
    }

    if (path === "/api/settings" && req.method === "GET") {
      const res = await sendToIPC({ action: "get_settings" });
      return Response.json(res);
    }

    if (path === "/api/settings" && req.method === "POST") {
      const body = await req.json();
      const res = await sendToIPC({ action: "update_settings", settings: body });
      return Response.json(res);
    }

    return Response.json({ error: "見つかりません" }, { status: 404 });
  } catch (err) {
    return Response.json(
      { error: `デーモンへの接続に失敗: ${err}` },
      { status: 502 }
    );
  }
}

// --- Server ---

export async function startServer(preferredPort?: number) {
  const port = preferredPort ?? 0; // 0 = OS picks available port

  // Try to connect to daemon first
  try {
    await ensureIPC();
  } catch {
    console.warn("警告: デーモンに接続できませんでした。リクエスト時に再接続を試みます。");
  }

  const server = Bun.serve({
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

  const actualPort = server.port;
  const url = `http://localhost:${actualPort}`;
  console.log(`LocalRunner Web UI: ${url}`);

  // Open browser
  Bun.spawn(["open", url], { stdout: "ignore", stderr: "ignore" });

  return server;
}
