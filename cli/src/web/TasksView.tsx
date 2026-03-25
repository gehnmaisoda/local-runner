import React, { useState, useEffect, useCallback } from "react";
import type { TaskStatus, TaskDefinition, ExecutionRecord } from "./types.ts";
import { formatDate, formatDuration, formatSchedule } from "./format.ts";
import { CompactLogRow, LogModal } from "./LogViewer.tsx";

interface Props {
  tasks: TaskStatus[];
  onRun: (id: string) => void;
  onStop: (id: string) => void;
  onToggle: (id: string) => void;
  onEdit: (task: TaskDefinition) => void;
  onDelete: (id: string) => void;
}

function StatusDot({ task }: { task: TaskStatus }) {
  if (task.isRunning) return <span className="status-dot running" />;
  if (!task.task.enabled) return <span className="status-dot disabled" />;
  if (task.lastRun?.status === "failure") return <span className="status-dot failure" />;
  if (task.lastRun?.status === "stopped") return <span className="status-dot stopped" />;
  if (task.lastRun?.status === "success") return <span className="status-dot success" />;
  return <span className="status-dot disabled" />;
}

const STATUS_ICON: Record<string, string> = {
  success: "\u2713",
  failure: "\u2717",
  stopped: "\u25A0",
};

function TaskCard({ task, onRun, onStop, onToggle, onEdit, onDelete }: {
  task: TaskStatus;
  onRun: () => void;
  onStop: () => void;
  onToggle: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const [history, setHistory] = useState<ExecutionRecord[]>([]);
  const [viewingLog, setViewingLog] = useState<ExecutionRecord | null>(null);

  const loadHistory = useCallback(async () => {
    try {
      const res = await fetch(`/api/history?taskId=${task.task.id}&limit=10`);
      const data = await res.json();
      const records: ExecutionRecord[] = data.history ?? [];
      records.sort((a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime());
      setHistory(records);
    } catch { /* ignore */ }
  }, [task.task.id]);

  // Reload history when expanded, or when running state / lastRun changes
  useEffect(() => {
    if (expanded) loadHistory();
  }, [expanded, loadHistory, task.lastRun?.id, task.isRunning]);

  const t = task.task;

  return (
    <>
      <div className={`task-card ${expanded ? "expanded" : ""} ${!t.enabled ? "disabled" : ""}`}>
        <div className="task-card-header" onClick={() => setExpanded(!expanded)}>
          <StatusDot task={task} />
          <div className="task-card-info">
            <span className="task-name">{t.name}</span>
            <span className="task-card-meta">
              <span className="task-card-schedule">{formatSchedule(t.schedule)}</span>
              {task.nextRunAt && (
                <>
                  <span className="task-card-sep">&middot;</span>
                  <span>Next: {formatDate(task.nextRunAt)}</span>
                </>
              )}
            </span>
          </div>
          <div className="task-card-right">
            {task.lastRun && (
              <span className={`task-card-last ${task.lastRun.status}`}>
                {STATUS_ICON[task.lastRun.status] ?? ""} {formatDuration(task.lastRun)}
              </span>
            )}
            <span className="task-card-chevron">{expanded ? "\u25B4" : "\u25BE"}</span>
          </div>
        </div>

        {expanded && (
          <div className="task-card-body">
            <div className="task-card-detail">
              <div className="task-detail-row">
                <span className="task-detail-label">Command</span>
                <pre className="task-detail-command">{t.command}</pre>
              </div>
              {t.working_directory && (
                <div className="task-detail-row">
                  <span className="task-detail-label">Directory</span>
                  <span className="task-detail-value mono">{t.working_directory}</span>
                </div>
              )}
              <div className="task-card-actions">
                {task.isRunning ? (
                  <button className="btn btn-stop" onClick={(e) => { e.stopPropagation(); onStop(); }}>Stop</button>
                ) : (
                  <button className="btn btn-run" onClick={(e) => { e.stopPropagation(); onRun(); }}>Run</button>
                )}
                <button className="btn btn-ghost" onClick={(e) => { e.stopPropagation(); onToggle(); }}>
                  {t.enabled ? "Disable" : "Enable"}
                </button>
                <button className="btn btn-ghost" onClick={(e) => { e.stopPropagation(); onEdit(); }}>Edit</button>
                <button className="btn btn-danger-ghost" onClick={(e) => { e.stopPropagation(); onDelete(); }}>Delete</button>
              </div>
            </div>

            {history.length > 0 && (
              <div className="task-card-history">
                <div className="task-card-history-title">Recent Runs</div>
                {history.map((r) => (
                  <CompactLogRow key={r.id} record={r} onClick={() => setViewingLog(r)} />
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {viewingLog && (
        <LogModal record={viewingLog} onClose={() => setViewingLog(null)} />
      )}
    </>
  );
}

export function TasksView({ tasks, onRun, onStop, onToggle, onEdit, onDelete }: Props) {
  if (tasks.length === 0) {
    return <div className="empty">No tasks defined yet. Create one to get started.</div>;
  }

  return (
    <div className="task-list">
      {tasks.map((t) => (
        <TaskCard
          key={t.task.id}
          task={t}
          onRun={() => onRun(t.task.id)}
          onStop={() => onStop(t.task.id)}
          onToggle={() => onToggle(t.task.id)}
          onEdit={() => onEdit(t.task)}
          onDelete={() => onDelete(t.task.id)}
        />
      ))}
    </div>
  );
}
