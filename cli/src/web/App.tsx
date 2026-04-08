import React, { useState, useCallback } from "react";
import { useTasks, useTimeline, useWebSocket, useSettings, runTask, stopTask, saveTask, deleteTask, updateSettings } from "./hooks.ts";
import { TasksView } from "./TasksView.tsx";
import { TimelineView } from "./TimelineView.tsx";
import { SettingsView } from "./SettingsView.tsx";
import { ToastContainer } from "./Toast.tsx";
import type { TaskDefinition } from "./types.ts";

type Tab = "tasks" | "timeline" | "settings";

function DisconnectedView({ onRetry, retrying }: { onRetry: () => void; retrying: boolean }) {
  return (
    <div className="onboarding">
      <div className="onboarding-card">
        <div className="onboarding-icon">
          <svg viewBox="0 0 48 48" fill="none">
            <rect x="4" y="4" width="40" height="40" rx="12" fill="var(--red-dim)" stroke="var(--red)" strokeWidth="1.5" />
            <path d="M16 16L32 32M32 16L16 32" stroke="var(--red)" strokeWidth="2.5" strokeLinecap="round" />
          </svg>
        </div>
        <h2 className="onboarding-title">デーモンに接続できません</h2>
        <p className="onboarding-desc">
          LocalRunner デーモンが起動していないか、<br />
          接続に問題が発生しています。
        </p>
        <button
          className="btn btn-primary onboarding-cta"
          onClick={onRetry}
          disabled={retrying}
        >
          {retrying ? "接続中..." : "再接続"}
        </button>
      </div>
    </div>
  );
}

export function App() {
  const [tab, setTab] = useState<Tab>("tasks");
  const { tasks, loading: tasksLoading, error: tasksError, reload: reloadTasks } = useTasks();
  const { history, reload: reloadTimeline } = useTimeline();
  const { settings, loading: settingsLoading, reload: reloadSettings } = useSettings();
  const [isNewTask, setIsNewTask] = useState(false);
  const [retrying, setRetrying] = useState(false);

  const handleMessage = useCallback(() => {
    reloadTasks();
    reloadTimeline();
  }, [reloadTasks, reloadTimeline]);

  const connected = useWebSocket(handleMessage);

  const daemonConnected = !tasksError;

  const handleRetry = async () => {
    setRetrying(true);
    await reloadTasks(false);
    setRetrying(false);
  };

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
        <span className={`conn-badge ${connected && daemonConnected ? "connected" : "disconnected"}`}>
          {connected && daemonConnected ? "接続中" : "切断"}
        </span>
      </header>

      <main>
        {!tasksLoading && !daemonConnected ? (
          <DisconnectedView onRetry={handleRetry} retrying={retrying} />
        ) : (
          <>
            <div className="tabs-toolbar">
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
                <button
                  className={`tab ${tab === "settings" ? "active" : ""}`}
                  onClick={() => setTab("settings")}
                >
                  設定
                </button>
              </div>
              {tab === "tasks" && (
                <button
                  className="btn btn-primary"
                  onClick={() => { setIsNewTask(true); }}
                >
                  + 新規タスク
                </button>
              )}
            </div>

            {tab === "tasks" && (
              <TasksView
                tasks={tasks}
                loading={tasksLoading}
                isNewTask={isNewTask}
                onNewTaskChange={setIsNewTask}
                onRun={handleRun}
                onStop={handleStop}
                onSave={handleSave}
                onDelete={handleDelete}
                slackConfigured={!!settings?.slack_bot_token}
              />
            )}
            {tab === "timeline" && <TimelineView history={history} />}
            {tab === "settings" && (
              <SettingsView
                settings={settings}
                loading={settingsLoading}
                onSave={async (s) => {
                  const ok = await updateSettings(s);
                  if (ok) reloadSettings();
                  return ok;
                }}
              />
            )}
          </>
        )}
      </main>

      <ToastContainer />
    </>
  );
}
