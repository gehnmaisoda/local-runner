import React, { useState, useCallback } from "react";
import { useTasks, useTimeline, useWebSocket, runTask, stopTask, toggleTask, saveTask, deleteTask } from "./hooks.ts";
import { TasksView } from "./TasksView.tsx";
import { TimelineView } from "./TimelineView.tsx";
import { TaskFormModal } from "./TaskForm.tsx";
import { ToastContainer } from "./Toast.tsx";
import type { TaskDefinition } from "./types.ts";

type Tab = "tasks" | "timeline";

export function App() {
  const [tab, setTab] = useState<Tab>("tasks");
  const { tasks, reload: reloadTasks } = useTasks();
  const { history, reload: reloadTimeline } = useTimeline();
  const [editing, setEditing] = useState<TaskDefinition | "new" | null>(null);

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
  const handleToggle = async (id: string) => {
    await toggleTask(id);
    reloadTasks();
  };
  const handleEdit = (task: TaskDefinition) => {
    setEditing(task);
  };
  const handleDelete = async (id: string) => {
    if (!confirm(`Delete task "${id}"?`)) return;
    await deleteTask(id);
    reloadTasks();
  };
  const handleSave = async (task: TaskDefinition) => {
    const ok = await saveTask(task);
    if (ok) {
      setEditing(null);
      reloadTasks();
    }
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
          {connected ? "Connected" : "Disconnected"}
        </span>
      </header>

      <main>
        <div className="tabs">
          <button
            className={`tab ${tab === "tasks" ? "active" : ""}`}
            onClick={() => setTab("tasks")}
          >
            Tasks
          </button>
          <button
            className={`tab ${tab === "timeline" ? "active" : ""}`}
            onClick={() => setTab("timeline")}
          >
            Timeline
          </button>
        </div>

        {tab === "tasks" && (
          <>
            <div className="toolbar">
              <button className="btn btn-primary" onClick={() => setEditing("new")}>
                + New Task
              </button>
            </div>
            <TasksView
              tasks={tasks}
              onRun={handleRun}
              onStop={handleStop}
              onToggle={handleToggle}
              onEdit={handleEdit}
              onDelete={handleDelete}
            />
          </>
        )}
        {tab === "timeline" && <TimelineView history={history} />}
      </main>

      {editing && (
        <TaskFormModal
          initial={editing === "new" ? undefined : editing}
          onSave={handleSave}
          onCancel={() => setEditing(null)}
        />
      )}

      <ToastContainer />
    </>
  );
}
