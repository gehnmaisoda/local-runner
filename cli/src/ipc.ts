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
  timeout?: number;
}

export interface Schedule {
  type: string;
  minute?: number;        // hourly: 0-59
  time?: string;          // daily/weekly/monthly: "HH:mm"
  weekday?: number;       // weekly: 1=Mon...7=Sun (ISO) (legacy single)
  weekdays?: number[];    // weekly: [1,3,5] = Mon/Wed/Fri
  month_days?: number[];  // monthly: [-1, 1, 15]
  expression?: string;    // cron
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
  status: "running" | "success" | "failure" | "stopped" | "timeout" | "pending";
}

export interface TaskStatus {
  task: TaskDefinition;
  lastRun?: ExecutionRecord;
  nextRunAt?: string;
  isRunning: boolean;
}

export interface GlobalSettings {
  slack_webhook_url?: string;
  default_timeout?: number;
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
  public onDisconnect?: () => void;

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
              p.reject(new Error("接続が切断されました"));
            }
            client.pending = [];
            client.onDisconnect?.();
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
          waiter.reject(new Error("IPC レスポンスの解析に失敗しました"));
        }
      }
    }
  }

  async send(request: IPCRequest, timeout = 5000): Promise<IPCResponse> {
    if (!this.socket) {
      throw new Error("デーモンに接続されていません。デーモンは起動していますか？");
    }
    const encoded = encodeMessage(request);
    this.socket.write(encoded);

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const idx = this.pending.indexOf(entry);
        if (idx !== -1) this.pending.splice(idx, 1);
        reject(new Error("IPC リクエストがタイムアウトしました"));
      }, timeout);

      const entry = {
        resolve: (value: IPCResponse) => {
          clearTimeout(timer);
          resolve(value);
        },
        reject: (reason: unknown) => {
          clearTimeout(timer);
          reject(reason);
        },
      };
      this.pending.push(entry);
    });
  }

  subscribe(callback: (notification: IPCNotification) => void) {
    this.onNotification = callback;
    // Fire-and-forget subscribe request
    if (this.socket) {
      this.socket.write(encodeMessage({ action: "subscribe" }));
    }
  }

  onNotify(callback: (notification: IPCNotification) => void) {
    this.onNotification = callback;
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
  await client.connect();
  return client;
}
