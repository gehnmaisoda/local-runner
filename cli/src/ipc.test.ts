import { test, expect, afterEach } from "bun:test";
import { IPCClient } from "./ipc.ts";
import { unlinkSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

function testSocketPath() {
  return join(tmpdir(), `lr-test-${Date.now()}-${Math.random().toString(36).slice(2)}.sock`);
}

// Wire format helper: 4-byte big-endian length prefix + JSON
function encodeResponse(obj: unknown): Buffer {
  const json = Buffer.from(JSON.stringify(obj), "utf-8");
  const header = Buffer.alloc(4);
  header.writeUInt32BE(json.length, 0);
  return Buffer.concat([header, json]);
}

const cleanupPaths: string[] = [];
const cleanupServers: { stop(): void }[] = [];

afterEach(() => {
  for (const s of cleanupServers) s.stop();
  cleanupServers.length = 0;
  for (const p of cleanupPaths) {
    try { unlinkSync(p); } catch {}
  }
  cleanupPaths.length = 0;
});

test("send() rejects with timeout when daemon does not respond", async () => {
  const sockPath = testSocketPath();
  cleanupPaths.push(sockPath);

  // Accept connections but never respond
  const server = Bun.listen({
    unix: sockPath,
    socket: {
      data() {},
      open() {},
      close() {},
    },
  });
  cleanupServers.push(server);

  const client = new IPCClient();
  await client.connect(sockPath);

  try {
    await expect(
      client.send({ action: "list_tasks" }, 100),
    ).rejects.toThrow("タイムアウト");
  } finally {
    client.close();
  }
});

test("send() resolves when daemon responds within timeout", async () => {
  const sockPath = testSocketPath();
  cleanupPaths.push(sockPath);

  const server = Bun.listen({
    unix: sockPath,
    socket: {
      data(socket) {
        socket.write(encodeResponse({ success: true, tasks: [] }));
      },
      open() {},
      close() {},
    },
  });
  cleanupServers.push(server);

  const client = new IPCClient();
  await client.connect(sockPath);

  try {
    const res = await client.send({ action: "list_tasks" }, 1000);
    expect(res.success).toBe(true);
  } finally {
    client.close();
  }
});

test("send() cleans up pending entry on timeout", async () => {
  const sockPath = testSocketPath();
  cleanupPaths.push(sockPath);

  const server = Bun.listen({
    unix: sockPath,
    socket: {
      data() {},
      open() {},
      close() {},
    },
  });
  cleanupServers.push(server);

  const client = new IPCClient();
  await client.connect(sockPath);

  try {
    // Send and let it timeout
    await client.send({ action: "list_tasks" }, 50).catch(() => {});
    // A second send should still work (pending queue not corrupted)
    await expect(
      client.send({ action: "list_tasks" }, 50),
    ).rejects.toThrow("タイムアウト");
  } finally {
    client.close();
  }
});

test("send() rejects immediately when not connected", async () => {
  const client = new IPCClient();

  await expect(
    client.send({ action: "list_tasks" }),
  ).rejects.toThrow("接続されていません");
});

test("send() receives systemLogs in response", async () => {
  const sockPath = testSocketPath();
  cleanupPaths.push(sockPath);

  const mockLogs = [
    { timestamp: "2026-04-06T09:00:00+09:00", tag: "Scheduler", message: "test msg" },
  ];

  const server = Bun.listen({
    unix: sockPath,
    socket: {
      data(socket) {
        socket.write(encodeResponse({ success: true, systemLogs: mockLogs }));
      },
      open() {},
      close() {},
    },
  });
  cleanupServers.push(server);

  const client = new IPCClient();
  await client.connect(sockPath);

  try {
    const res = await client.send({ action: "get_system_logs", limit: 1000 }, 1000);
    expect(res.success).toBe(true);
    expect(res.systemLogs).toHaveLength(1);
    expect(res.systemLogs![0].tag).toBe("Scheduler");
    expect(res.systemLogs![0].message).toBe("test msg");
  } finally {
    client.close();
  }
});

test("send() clear_system_logs returns success", async () => {
  const sockPath = testSocketPath();
  cleanupPaths.push(sockPath);

  const server = Bun.listen({
    unix: sockPath,
    socket: {
      data(socket) {
        socket.write(encodeResponse({ success: true }));
      },
      open() {},
      close() {},
    },
  });
  cleanupServers.push(server);

  const client = new IPCClient();
  await client.connect(sockPath);

  try {
    const res = await client.send({ action: "clear_system_logs" }, 1000);
    expect(res.success).toBe(true);
  } finally {
    client.close();
  }
});

test("connect() rejects when socket path does not exist", async () => {
  const client = new IPCClient();

  await expect(
    client.connect("/tmp/nonexistent-lr-test.sock"),
  ).rejects.toThrow();
});
