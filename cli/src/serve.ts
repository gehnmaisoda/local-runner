import { IPCClient, getSocketPath, type IPCNotification } from "./ipc.ts";
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
  ipcClient = new IPCClient();
  await ipcClient.connect();
  ipcClient.subscribe((notification: IPCNotification) => {
    const msg = JSON.stringify({ type: "notification", ...notification });
    for (const ws of wsClients) {
      ws.send(msg);
    }
  });
  return ipcClient;
}

// --- API handlers ---

async function handleAPI(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname;

  try {
    const client = await ensureIPC();

    if (path === "/api/tasks" && req.method === "GET") {
      const res = await client.send({ action: "list_tasks" });
      return Response.json(res);
    }

    if (path === "/api/history" && req.method === "GET") {
      const taskId = url.searchParams.get("taskId") ?? undefined;
      const limit = parseInt(url.searchParams.get("limit") ?? "50", 10);
      const res = await client.send({ action: "get_history", taskId, limit });
      return Response.json(res);
    }

    if (path.startsWith("/api/tasks/") && req.method === "POST") {
      const taskId = path.split("/")[3];
      const action = path.split("/")[4]; // run, stop, toggle
      if (action === "run") {
        const res = await client.send({ action: "run_task", taskId });
        return Response.json(res);
      }
      if (action === "stop") {
        const res = await client.send({ action: "stop_task", taskId });
        return Response.json(res);
      }
      if (action === "toggle") {
        const res = await client.send({ action: "toggle_task", taskId });
        return Response.json(res);
      }
    }

    if (path === "/api/tasks" && req.method === "POST") {
      const body = await req.json();
      const res = await client.send({ action: "save_task", task: body });
      return Response.json(res);
    }

    if (path.startsWith("/api/tasks/") && req.method === "DELETE") {
      const taskId = path.split("/")[3];
      const res = await client.send({ action: "delete_task", taskId });
      return Response.json(res);
    }

    if (path === "/api/settings" && req.method === "GET") {
      const res = await client.send({ action: "get_settings" });
      return Response.json(res);
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  } catch (err) {
    ipcClient = null;
    return Response.json(
      { error: `Daemon connection failed: ${err}` },
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
    console.warn("Warning: Could not connect to daemon. Will retry on requests.");
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
        return new Response("WebSocket upgrade failed", { status: 400 });
      }

      // API routes
      if (url.pathname.startsWith("/api/")) {
        return handleAPI(req);
      }

      return new Response("Not found", { status: 404 });
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
