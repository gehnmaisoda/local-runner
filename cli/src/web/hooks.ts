import { useState, useEffect, useCallback, useRef } from "react";
import type { TaskStatus, ExecutionRecord, TaskDefinition } from "./types.ts";

export function useTasks() {
  const [tasks, setTasks] = useState<TaskStatus[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/tasks");
      const data = await res.json();
      setTasks(data.tasks ?? []);
    } catch {
      // ignore
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  return { tasks, loading, reload: load };
}

export function useTimeline(limit = 50) {
  const [history, setHistory] = useState<ExecutionRecord[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await fetch(`/api/history?limit=${limit}`);
      const data = await res.json();
      setHistory(data.history ?? []);
    } catch {
      // ignore
    } finally {
      setLoading(false);
    }
  }, [limit]);

  useEffect(() => { load(); }, [load]);

  return { history, loading, reload: load };
}

export function useWebSocket(onMessage: () => void) {
  const [connected, setConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    function connect() {
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      const ws = new WebSocket(`${proto}//${location.host}/ws`);

      ws.onopen = () => setConnected(true);
      ws.onclose = () => {
        setConnected(false);
        setTimeout(connect, 3000);
      };
      ws.onmessage = () => onMessage();

      wsRef.current = ws;
    }

    connect();
    return () => { wsRef.current?.close(); };
  }, [onMessage]);

  return connected;
}

// --- Toast notifications ---

type ToastListener = (message: string) => void;
let toastListener: ToastListener | null = null;

export function onToast(listener: ToastListener) {
  toastListener = listener;
}

function showError(msg: string) {
  toastListener?.(msg);
}

// --- API calls with error handling ---

async function apiCall(url: string, options?: RequestInit): Promise<Response> {
  const res = await fetch(url, options);
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error ?? `Request failed (${res.status})`);
  }
  const data = await res.json();
  if (data.success === false) {
    throw new Error(data.error ?? "Operation failed");
  }
  return data;
}

export async function runTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}/run`, { method: "POST" });
  } catch (e: any) {
    showError(`Failed to run task: ${e.message}`);
  }
}

export async function stopTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}/stop`, { method: "POST" });
  } catch (e: any) {
    showError(`Failed to stop task: ${e.message}`);
  }
}

export async function toggleTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}/toggle`, { method: "POST" });
  } catch (e: any) {
    showError(`Failed to toggle task: ${e.message}`);
  }
}

export async function saveTask(task: TaskDefinition): Promise<boolean> {
  try {
    await apiCall("/api/tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(task),
    });
    return true;
  } catch (e: any) {
    showError(`Failed to save task: ${e.message}`);
    return false;
  }
}

export async function deleteTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}`, { method: "DELETE" });
  } catch (e: any) {
    showError(`Failed to delete task: ${e.message}`);
  }
}
