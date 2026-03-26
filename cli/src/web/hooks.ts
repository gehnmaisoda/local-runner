import { useState, useEffect, useCallback, useRef } from "react";
import type { TaskStatus, ExecutionRecord, TaskDefinition } from "./types.ts";
import { formatCountdown } from "./format.ts";

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
  const retryRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;

    function connect() {
      if (!mountedRef.current) return;
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      const ws = new WebSocket(`${proto}//${location.host}/ws`);

      ws.onopen = () => { if (mountedRef.current) setConnected(true); };
      ws.onclose = () => {
        if (!mountedRef.current) return;
        setConnected(false);
        retryRef.current = setTimeout(connect, 3000);
      };
      ws.onmessage = () => { if (mountedRef.current) onMessage(); };

      wsRef.current = ws;
    }

    connect();
    return () => {
      mountedRef.current = false;
      clearTimeout(retryRef.current);
      wsRef.current?.close();
    };
  }, [onMessage]);

  return connected;
}

export function useCountdown(isoTarget: string | undefined): string | null {
  const targetMs = isoTarget ? new Date(isoTarget).getTime() : null;

  const [text, setText] = useState<string | null>(() =>
    targetMs != null ? formatCountdown(targetMs) : null,
  );

  useEffect(() => {
    if (targetMs == null) { setText(null); return; }
    setText(formatCountdown(targetMs));
    const id = setInterval(() => setText(formatCountdown(targetMs)), 1000);
    return () => clearInterval(id);
  }, [targetMs]);

  return text;
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

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

// --- API calls with error handling ---

async function apiCall(url: string, options?: RequestInit): Promise<Response> {
  const res = await fetch(url, options);
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.error ?? `リクエスト失敗 (${res.status})`);
  }
  const data = await res.json();
  if (data.success === false) {
    throw new Error(data.error ?? "操作に失敗しました");
  }
  return data;
}

export async function runTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}/run`, { method: "POST" });
  } catch (e: unknown) {
    showError(`タスクの実行に失敗: ${errorMessage(e)}`);
  }
}

export async function stopTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}/stop`, { method: "POST" });
  } catch (e: unknown) {
    showError(`タスクの停止に失敗: ${errorMessage(e)}`);
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
  } catch (e: unknown) {
    showError(`タスクの保存に失敗: ${errorMessage(e)}`);
    return false;
  }
}

export async function deleteTask(id: string) {
  try {
    await apiCall(`/api/tasks/${id}`, { method: "DELETE" });
  } catch (e: unknown) {
    showError(`タスクの削除に失敗: ${errorMessage(e)}`);
  }
}
