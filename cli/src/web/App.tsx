import React, { useState, useCallback } from "react";
import { useTasks, useTimeline, useWebSocket, runTask, stopTask, saveTask, deleteTask } from "./hooks.ts";
import { TasksView } from "./TasksView.tsx";
import { TimelineView } from "./TimelineView.tsx";
import { ToastContainer } from "./Toast.tsx";
import type { TaskDefinition } from "./types.ts";

type Tab = "tasks" | "timeline";

export function App() {
  const [tab, setTab] = useState<Tab>("tasks");
  const { tasks, loading: tasksLoading, reload: reloadTasks } = useTasks();
  const { history, reload: reloadTimeline } = useTimeline();

  const handleMessage = useCallback(() => {
    reloadTasks();
    reloadTimeline();
  }, [reloadTasks, reloadTimeline]);

  const connected = useWebSocket(handleMessage);

  const handleRun = async (id: string) => {
    await runTask(id);
    reloadTasks();
  };
  const handleStop = async (id: string) => {
    await stopTask(id);
    reloadTasks();
  };
  const handleSave = async (task: TaskDefinition): Promise<boolean> => {
    const ok = await saveTask(task);
    if (ok) reloadTasks();
    return ok;
  };
  const handleDelete = async (id: string, name: string) => {
    if (!confirm(`タスク "${name}" を削除しますか？\n\n実行ログもすべて削除されます。`)) return;
    await deleteTask(id);
    reloadTasks();
  };

  return (
    <>
      <header>
        <div className="header-brand">
          <div className="header-logo">
            <svg viewBox="0 0 16 16" fill="none">
              <path d="M4 3L12 8L4 13V3Z" fill="#111110"/>
            </svg>
          </div>
          <h1>LocalRunner</h1>
        </div>
        <span className={`conn-badge ${connected ? "connected" : "disconnected"}`}>
          {connected ? "接続中" : "切断"}
        </span>
      </header>

      <main>
        <div className="tabs">
          <button
            className={`tab ${tab === "tasks" ? "active" : ""}`}
            onClick={() => setTab("tasks")}
          >
            タスク
          </button>
          <button
            className={`tab ${tab === "timeline" ? "active" : ""}`}
            onClick={() => setTab("timeline")}
          >
            実行ログ
          </button>
        </div>

        {tab === "tasks" && (
          <TasksView
            tasks={tasks}
            loading={tasksLoading}
            onRun={handleRun}
            onStop={handleStop}
            onSave={handleSave}
            onDelete={handleDelete}
          />
        )}
        {tab === "timeline" && <TimelineView history={history} />}
      </main>

      <ToastContainer />
    </>
  );
}
