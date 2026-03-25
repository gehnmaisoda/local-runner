import { connect, type Socket } from "bun";
import { homedir } from "os";
import { join } from "path";

// --- Types matching Swift IPCProtocol ---

export interface TaskDefinition {
  id: string;
  name: string;
  description?: string;
  command: string;
  working_directory?: string;
  schedule: Schedule;
  enabled: boolean;
  catch_up: boolean;
  notify_on_failure: boolean;
}

export interface Schedule {
  type: string;
  minute?: number;      // hourly: 0-59
  time?: string;        // daily/weekly: "HH:mm"
  weekday?: number;     // weekly: 1=Mon...7=Sun (ISO)
  expression?: string;  // cron
}

export interface ExecutionRecord {
  id: string;
  taskId: string;
  taskName: string;
  startedAt: string;
  finishedAt?: string;
  exitCode?: number;
  stdout: string;
  stderr: string;
  status: "running" | "success" | "failure" | "stopped";
}

export interface TaskStatus {
  task: TaskDefinition;
  lastRun?: ExecutionRecord;
  nextRunAt?: string;
  isRunning: boolean;
}

export interface GlobalSettings {
  slack_webhook_url?: string;
}

export interface IPCRequest {
  action: string;
  taskId?: string;
  limit?: number;
  task?: TaskDefinition;
  settings?: GlobalSettings;
}

export interface IPCResponse {
  success: boolean;
  error?: string;
  tasks?: TaskStatus[];
  history?: ExecutionRecord[];
  settings?: GlobalSettings;
}

export interface IPCNotification {
  event: string;
  taskId?: string;
  record?: ExecutionRecord;
}

// --- Socket path ---

const isDev = process.env.LOCAL_RUNNER_DEV === "1";
const appName = isDev ? "LocalRunner-Dev" : "LocalRunner";

export function getSocketPath(): string {
  return join(
    homedir(),
    "Library",
    "Application Support",
    appName,
    "daemon.sock"
  );
}

// --- Wire format: 4-byte big-endian length prefix + JSON ---

function encodeMessage(obj: unknown): Buffer {
  const json = Buffer.from(JSON.stringify(obj), "utf-8");
  const header = Buffer.alloc(4);
  header.writeUInt32BE(json.length, 0);
  return Buffer.concat([header, json]);
}

// --- IPC Client ---

export class IPCClient {
  private socket: Socket<{ buffer: Buffer }> | null = null;
  private buffer = Buffer.alloc(0);
  private pending: Array<{
    resolve: (value: IPCResponse) => void;
    reject: (reason: unknown) => void;
  }> = [];
  private onNotification?: (notification: IPCNotification) => void;

  async connect(socketPath?: string): Promise<void> {
    const path = socketPath ?? getSocketPath();
    return new Promise((resolve, reject) => {
      const client = this;
      connect({
        unix: path,
        socket: {
          open(socket) {
            client.socket = socket;
            client.buffer = Buffer.alloc(0);
            resolve();
          },
          data(_socket, data) {
            client.handleData(Buffer.from(data));
          },
          close() {
            client.socket = null;
            for (const p of client.pending) {
              p.reject(new Error("Connection closed"));
            }
            client.pending = [];
          },
          error(_socket, error) {
            if (client.socket === null) {
              reject(error);
            }
          },
          connectError(_socket, error) {
            reject(error);
          },
        },
        data: { buffer: Buffer.alloc(0) },
      });
    });
  }

  private handleData(data: Buffer) {
    this.buffer = Buffer.concat([this.buffer, data]);

    while (this.buffer.length >= 4) {
      const msgLen = this.buffer.readUInt32BE(0);
      const totalLen = 4 + msgLen;
      if (this.buffer.length < totalLen) break;

      const jsonBuf = this.buffer.subarray(4, totalLen);
      this.buffer = this.buffer.subarray(totalLen);

      try {
        const parsed = JSON.parse(jsonBuf.toString("utf-8"));

        // Distinguish notification vs response
        if ("event" in parsed) {
          this.onNotification?.(parsed as IPCNotification);
        } else {
          const waiter = this.pending.shift();
          if (waiter) {
            waiter.resolve(parsed as IPCResponse);
          }
        }
      } catch {
        const waiter = this.pending.shift();
        if (waiter) {
          waiter.reject(new Error("Failed to parse IPC response"));
        }
      }
    }
  }

  async send(request: IPCRequest): Promise<IPCResponse> {
    if (!this.socket) {
      throw new Error("Not connected to helper. Is LocalRunnerHelper running?");
    }
    const encoded = encodeMessage(request);
    this.socket.write(encoded);

    return new Promise((resolve, reject) => {
      this.pending.push({ resolve, reject });
    });
  }

  subscribe(callback: (notification: IPCNotification) => void) {
    this.onNotification = callback;
    // Fire-and-forget subscribe request
    if (this.socket) {
      this.socket.write(encodeMessage({ action: "subscribe" }));
    }
  }

  close() {
    this.socket?.end();
    this.socket = null;
  }

  get connected(): boolean {
    return this.socket !== null;
  }
}

// --- Convenience functions ---

export async function createClient(): Promise<IPCClient> {
  const client = new IPCClient();
  try {
    await client.connect();
  } catch {
    console.error(
      "Failed to connect to LocalRunnerHelper. Is it running?\n" +
        `  Socket: ${getSocketPath()}`
    );
    process.exit(1);
  }
  return client;
}
