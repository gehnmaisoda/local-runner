import React, { useState, useEffect, useCallback, useRef } from "react";
import type { TaskStatus, TaskDefinition, ExecutionRecord, Schedule } from "./types.ts";
import { formatDate, formatDuration, formatSchedule, statusIcon } from "./format.ts";
import { LogModal } from "./LogViewer.tsx";
import { useCountdown } from "./hooks.ts";

// --- Props ---

interface Props {
  tasks: TaskStatus[];
  loading: boolean;
  onRun: (id: string) => void;
  onStop: (id: string) => void;
  onSave: (task: TaskDefinition) => Promise<boolean>;
  onDelete: (id: string, name: string) => void;
}

// --- Shared components ---

function StatusDot({ task }: { task: TaskStatus }) {
  if (task.isRunning) return <span className="status-dot running" />;
  if (task.lastRun?.status === "failure") return <span className="status-dot failure" />;
  if (task.lastRun?.status === "stopped") return <span className="status-dot stopped" />;
  if (task.lastRun?.status === "success") return <span className="status-dot success" />;
  return <span className="status-dot idle" />;
}


function PlayIcon() {
  return (
    <svg className="btn-icon" viewBox="0 0 16 16" fill="none">
      <path d="M4 2.5L13 8L4 13.5V2.5Z" fill="currentColor" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg className="btn-icon" viewBox="0 0 16 16" fill="none">
      <rect x="3" y="3" width="10" height="10" rx="1.5" fill="currentColor" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg className="btn-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2.5 4.5h11M5.5 4.5V3a1 1 0 011-1h3a1 1 0 011 1v1.5M6.5 7v4M9.5 7v4M3.5 4.5l.5 8.5a1 1 0 001 1h6a1 1 0 001-1l.5-8.5" />
    </svg>
  );
}

// --- Log Row ---

export function StatusResult({ status, duration }: { status: string; duration: string }) {
  return (
    <span className={`status-result ${status}`}>
      <span className="status-result-icon">{statusIcon(status as ExecutionRecord["status"])}</span>
      {duration}
    </span>
  );
}

function LogRow({ record, onClick }: { record: ExecutionRecord; onClick: () => void }) {
  return (
    <div className="log-row" onClick={onClick}>
      <div className="log-row-header">
        <span className={`status-dot ${record.status}`} />
        <span className="log-row-time">{formatDate(record.startedAt)}</span>
        <StatusResult status={record.status} duration={formatDuration(record)} />
      </div>
    </div>
  );
}

// --- List Item ---

function TaskListItem({ task, selected, onSelect }: {
  task: TaskStatus;
  selected: boolean;
  onSelect: () => void;
}) {
  return (
    <div
      className={`task-list-item ${selected ? "selected" : ""}`}
      onClick={onSelect}
    >
      <StatusDot task={task} />
      <div className="task-list-item-info">
        <span className="task-list-item-name">{task.task.name}</span>
        <span className="task-list-item-meta">{formatSchedule(task.task.schedule)}</span>
      </div>
      {task.lastRun && (
        <StatusResult status={task.lastRun.status} duration={formatDuration(task.lastRun)} />
      )}
    </div>
  );
}

// --- Constants ---

const SCHEDULE_TYPES = [
  { value: "every_minute", label: "毎分" },
  { value: "hourly", label: "毎時" },
  { value: "daily", label: "毎日" },
  { value: "weekly", label: "毎週" },
  { value: "monthly", label: "毎月" },
  { value: "cron", label: "cron 式" },
] as const;

const WEEKDAYS = [
  { value: 1, label: "月" },
  { value: 2, label: "火" },
  { value: 3, label: "水" },
  { value: 4, label: "木" },
  { value: 5, label: "金" },
  { value: 6, label: "土" },
  { value: 7, label: "日" },
];

const MONTH_DAYS = Array.from({ length: 31 }, (_, i) => i + 1);

// --- Helpers ---

function generateId(): string {
  const chars = "abcdefghijklmnopqrstuvwxyz0123456789";
  let id = "task-";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

function parseTime(time: string | undefined): { hour: number; minute: number } {
  if (!time) return { hour: 0, minute: 0 };
  const [h, m] = time.split(":").map(Number);
  return { hour: h ?? 0, minute: m ?? 0 };
}

function formatTimeValue(hour: number, minute: number): string {
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function buildSchedule(
  type: string, hour: number, minute: number,
  weekdays: number[], monthDays: number[], cronExpr: string,
): Schedule {
  const time = formatTimeValue(hour, minute);
  switch (type) {
    case "hourly":  return { type, minute };
    case "daily":   return { type, time };
    case "weekly":  return { type, time, weekdays };
    case "monthly": return { type, time, month_days: monthDays };
    case "cron":    return { type, expression: cronExpr };
    default:        return { type };
  }
}

// --- Numeric Input (free-edit, validate on blur) ---

function NumInput({ value, onChange, min, max, className }: {
  value: number;
  onChange: (v: number) => void;
  min: number;
  max: number;
  className: string;
}) {
  const [draft, setDraft] = useState(String(value).padStart(2, "0"));
  const [focused, setFocused] = useState(false);

  useEffect(() => { if (!focused) setDraft(String(value).padStart(2, "0")); }, [value, focused]);

  return (
    <input
      className={className}
      type="text"
      inputMode="numeric"
      value={draft}
      onFocus={() => setFocused(true)}
      onChange={(e) => {
        const raw = e.target.value.replace(/[^0-9]/g, "");
        setDraft(raw);
        const n = parseInt(raw, 10);
        if (!isNaN(n) && n >= min && n <= max) onChange(n);
      }}
      onBlur={() => {
        setFocused(false);
        const n = parseInt(draft, 10);
        const clamped = isNaN(n) || n < min ? min : n > max ? max : n;
        onChange(clamped);
        setDraft(String(clamped).padStart(2, "0"));
      }}
    />
  );
}

// --- Detail Panel ---

interface DetailProps {
  task?: TaskDefinition;
  taskStatus?: TaskStatus;
  isNew: boolean;
  onSave: (task: TaskDefinition) => Promise<boolean>;
  onRun: () => void;
  onStop: () => void;
  onDelete: () => void;
}

const LOG_PAGE_SIZE = 15;

function TaskDetailPanel({ task, taskStatus, isNew, onSave, onRun, onStop, onDelete }: DetailProps) {
  const countdown = useCountdown(taskStatus?.nextRunAt);
  const [autoId] = useState(() => generateId());

  const [name, setName] = useState(task?.name ?? "");
  const [command, setCommand] = useState(task?.command ?? "");
  const [workingDirectory, setWorkingDirectory] = useState(task?.working_directory ?? "");
  const [dirError, setDirError] = useState<string | null>(null);
  const dirValidating = useRef(false);
  const [catchUp, setCatchUp] = useState(task?.catch_up ?? true);
  const [notifyOnFailure, setNotifyOnFailure] = useState(task?.notify_on_failure ?? false);

  const [scheduleType, setScheduleType] = useState(task?.schedule.type ?? "daily");
  const initialTime = parseTime(task?.schedule.time);
  const [hour, setHour] = useState(task?.schedule.time ? initialTime.hour : 9);
  const [minute, setMinute] = useState(
    task?.schedule.type === "hourly" ? (task?.schedule.minute ?? 0) : initialTime.minute,
  );
  const [weekdays, setWeekdays] = useState<number[]>(() => {
    if (task?.schedule.weekdays && task.schedule.weekdays.length > 0) return task.schedule.weekdays;
    return [task?.schedule.weekday ?? 1];
  });
  const [monthDays, setMonthDays] = useState<number[]>(() => {
    if (task?.schedule.month_days && task.schedule.month_days.length > 0) return task.schedule.month_days;
    return [1];
  });
  const [cronExpr, setCronExpr] = useState(task?.schedule.expression ?? "");

  const toggleWeekday = (day: number) => {
    setWeekdays((prev) => {
      const next = prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day];
      return next.length > 0 ? next : prev;
    });
  };

  const toggleMonthDay = (day: number) => {
    setMonthDays((prev) => {
      const next = prev.includes(day) ? prev.filter((d) => d !== day) : [...prev, day];
      return next.length > 0 ? next : prev;
    });
  };

  const [creating, setCreating] = useState(false);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved">("idle");

  // History
  const [history, setHistory] = useState<ExecutionRecord[]>([]);
  const [historyLimit, setHistoryLimit] = useState(LOG_PAGE_SIZE);
  const [hasMore, setHasMore] = useState(false);
  const [viewingLog, setViewingLog] = useState<ExecutionRecord | null>(null);

  const loadHistory = useCallback(async (limit: number) => {
    if (!task?.id) return;
    try {
      const res = await fetch(`/api/history?taskId=${task.id}&limit=${limit + 1}`);
      const data = await res.json();
      const records: ExecutionRecord[] = data.history ?? [];
      records.sort((a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime());
      setHasMore(records.length > limit);
      setHistory(records.slice(0, limit));
    } catch { /* ignore */ }
  }, [task?.id]);

  useEffect(() => {
    loadHistory(historyLimit);
  }, [loadHistory, historyLimit, taskStatus?.lastRun?.id, taskStatus?.isRunning]);

  const handleLoadMore = () => {
    setHistoryLimit((prev) => prev + LOG_PAGE_SIZE);
  };

  // --- Auto-save (existing tasks only) ---
  const onSaveRef = useRef(onSave);
  useEffect(() => { onSaveRef.current = onSave; });
  const isFirstRender = useRef(true);

  useEffect(() => {
    if (isNew || !task?.id) return;
    if (isFirstRender.current) { isFirstRender.current = false; return; }
    if (!name.trim() || !command || dirValidating.current) { setSaveStatus("idle"); return; }

    setSaveStatus("idle");
    const taskObj: TaskDefinition = {
      id: task.id,
      name: name.trim(),
      command,
      working_directory: workingDirectory.trim() || undefined,
      schedule: buildSchedule(scheduleType, hour, minute, weekdays, monthDays, cronExpr),
      enabled: task.enabled,
      catch_up: catchUp,
      notify_on_failure: notifyOnFailure,
    };

    const timer = setTimeout(async () => {
      setSaveStatus("saving");
      const ok = await onSaveRef.current(taskObj);
      setSaveStatus(ok ? "saved" : "idle");
    }, 600);

    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isNew, task?.id, name, command, workingDirectory, scheduleType, hour, minute, JSON.stringify(weekdays), JSON.stringify(monthDays), cronExpr, catchUp, notifyOnFailure]);

  // --- Create (new tasks only) ---
  const handleCreate = async () => {
    setCreating(true);
    await onSave({
      id: autoId,
      name: name.trim(),
      command,
      working_directory: workingDirectory.trim() || undefined,
      schedule: buildSchedule(scheduleType, hour, minute, weekdays, monthDays, cronExpr),
      enabled: true,
      catch_up: catchUp,
      notify_on_failure: notifyOnFailure,
    });
    setCreating(false);
  };

  return (
    <div className="detail-panel">
      <div className="detail-header">
        <input
          className="detail-name-input"
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="タスク名"
          autoFocus={isNew}
        />
        <div className="detail-header-actions">
          {!isNew && (
            <span className={`save-status ${saveStatus}`}>
              {saveStatus === "saving" ? "保存中..." : saveStatus === "saved" ? "\u2713" : ""}
            </span>
          )}
          {!isNew && taskStatus && (
            taskStatus.isRunning ? (
              <button className="btn btn-stop" onClick={onStop}><StopIcon />停止</button>
            ) : (
              <button className="btn btn-run" onClick={onRun}><PlayIcon />実行</button>
            )
          )}
          {isNew && (
            <button
              className="btn btn-primary"
              onClick={handleCreate}
              disabled={creating || !name.trim() || !command}
            >
              作成
            </button>
          )}
        </div>
      </div>

      <div className={`detail-body ${!isNew ? "two-col" : ""}`}>
        <div className="detail-col-form">
          <div className="detail-section">
            <label className="detail-label">実行コマンド</label>
            <textarea
              className="form-textarea"
              value={command}
              onChange={(e) => setCommand(e.target.value)}
              placeholder="echo 'hello world'"
              rows={6}
            />
          </div>

          <div className="detail-section">
            <label className="detail-label">実行ディレクトリ</label>
            <input
              className={`form-input ${dirError ? "input-error" : ""}`}
              type="text"
              value={workingDirectory}
              onChange={(e) => { setWorkingDirectory(e.target.value); setDirError(null); }}
              onBlur={async () => {
                const trimmed = workingDirectory.trim();
                if (!trimmed) { setDirError(null); return; }
                dirValidating.current = true;
                try {
                  const res = await fetch(`/api/check-dir?path=${encodeURIComponent(trimmed)}`);
                  const data = await res.json();
                  setDirError(data.exists ? null : "ディレクトリが存在しません");
                } catch {
                  setDirError(null);
                } finally {
                  dirValidating.current = false;
                }
              }}
              placeholder="~/projects/myapp"
            />
            {dirError && <div className="field-error">{dirError}</div>}
            <div className="field-hint-small">※ 省略時はホームディレクトリで実行されます</div>
          </div>

          <div className="detail-section">
            <label className="detail-label">実行スケジュール (JST)</label>
            <div className="sched">
              <div className="sched-pills">
                {SCHEDULE_TYPES.map((st) => (
                  <button
                    key={st.value}
                    type="button"
                    className={`sched-pill ${scheduleType === st.value ? "active" : ""}`}
                    onClick={() => setScheduleType(st.value)}
                  >
                    {st.label}
                  </button>
                ))}
              </div>

              {scheduleType === "every_minute" && (
                <div className="sched-hint">毎分実行されます</div>
              )}

              {scheduleType === "hourly" && (
                <div className="sched-sentence">
                  毎時
                  <div className="sched-time-box">
                    <NumInput className="sched-time-m" min={0} max={59} value={minute} onChange={setMinute} />
                  </div>
                  分に実行
                </div>
              )}

              {scheduleType === "daily" && (
                <div className="sched-sentence">
                  毎日
                  <div className="sched-time-box">
                    <NumInput className="sched-time-h" min={0} max={23} value={hour} onChange={setHour} />
                    <span className="sched-time-sep">:</span>
                    <NumInput className="sched-time-m" min={0} max={59} value={minute} onChange={setMinute} />
                  </div>
                  に実行
                </div>
              )}

              {scheduleType === "weekly" && (
                <>
                  <div className="sched-weekdays">
                    {WEEKDAYS.map((d) => (
                      <button
                        key={d.value}
                        type="button"
                        className={`weekday-pill ${weekdays.includes(d.value) ? "active" : ""}`}
                        onClick={() => toggleWeekday(d.value)}
                      >
                        {d.label}
                      </button>
                    ))}
                  </div>
                  <div className="sched-sentence">
                    <div className="sched-time-box">
                      <NumInput className="sched-time-h" min={0} max={23} value={hour} onChange={setHour} />
                      <span className="sched-time-sep">:</span>
                      <NumInput className="sched-time-m" min={0} max={59} value={minute} onChange={setMinute} />
                    </div>
                    に実行
                  </div>
                </>
              )}

              {scheduleType === "monthly" && (
                <>
                  <div className="sched-monthdays">
                    {MONTH_DAYS.map((d) => (
                      <button
                        key={d}
                        type="button"
                        className={`monthday-pill ${monthDays.includes(d) ? "active" : ""}`}
                        onClick={() => toggleMonthDay(d)}
                      >
                        {d}
                      </button>
                    ))}
                    <button
                      type="button"
                      className={`monthday-pill last-day ${monthDays.includes(-1) ? "active" : ""}`}
                      onClick={() => toggleMonthDay(-1)}
                    >
                      月末
                    </button>
                  </div>
                  <div className="sched-sentence">
                    <div className="sched-time-box">
                      <NumInput className="sched-time-h" min={0} max={23} value={hour} onChange={setHour} />
                      <span className="sched-time-sep">:</span>
                      <NumInput className="sched-time-m" min={0} max={59} value={minute} onChange={setMinute} />
                    </div>
                    に実行
                  </div>
                </>
              )}

              {scheduleType === "cron" && (
                <input
                  className="form-input sched-cron"
                  type="text"
                  value={cronExpr}
                  onChange={(e) => setCronExpr(e.target.value)}
                  placeholder="*/15 * * * *"
                />
              )}
            </div>
          </div>

          <div className="detail-section">
            <label className="detail-label">オプション</label>
            <div className="checkbox-group">
              <label className="checkbox-label">
                <input type="checkbox" checked={catchUp} onChange={(e) => setCatchUp(e.target.checked)} />
                スリープ復帰時に未実行分を1回実行
                <span className="tooltip-wrap">
                  <span className="tooltip-hint">?</span>
                  <span className="tooltip-bubble">
                    スリープ復帰時に、実行されなかったスケジュールがあれば <strong>1回だけ</strong> 再実行します。複数回分溜まっていても実行は1回です。
                    <br /><br />
                    遡る範囲は直前のスリープ期間のみです。
                    <br /><br />
                    例: 毎朝 08:00 のタスクで 11:00 に復帰 → 即座に1回実行
                  </span>
                </span>
              </label>
              <label className="checkbox-label">
                <input type="checkbox" checked={notifyOnFailure} onChange={(e) => setNotifyOnFailure(e.target.checked)} />
                失敗時に通知 (Slack)
              </label>
            </div>
          </div>

          {!isNew && (
            <div className="detail-section detail-delete">
              <button className="btn btn-danger-ghost" onClick={onDelete}>
                <TrashIcon />タスクを削除
              </button>
            </div>
          )}
        </div>

        {!isNew && (
          <div className="detail-col-log">
            {taskStatus?.nextRunAt && (
              <div className="detail-section">
                <label className="detail-label">次回実行</label>
                <span className="next-run-badge">
                  {formatDate(taskStatus.nextRunAt)}
                  {countdown && <span className="next-run-countdown">（{countdown}）</span>}
                </span>
              </div>
            )}
            <label className="detail-label">実行ログ</label>
            {history.length > 0 ? (
              <div className="log-list">
                {history.map((r) => (
                  <LogRow key={r.id} record={r} onClick={() => setViewingLog(r)} />
                ))}
                {hasMore && (
                  <button className="load-more-btn" onClick={handleLoadMore}>
                    もっと読み込む
                  </button>
                )}
              </div>
            ) : (
              <div className="log-empty-hint">まだ実行されていません</div>
            )}
          </div>
        )}
      </div>

      {viewingLog && (
        <LogModal record={viewingLog} onClose={() => setViewingLog(null)} />
      )}
    </div>
  );
}

// --- Empty / Onboarding State ---

function EmptyState({ onCreate }: { onCreate: () => void }) {
  return (
    <div className="onboarding">
      <div className="onboarding-card">
        <div className="onboarding-icon">
          <svg viewBox="0 0 48 48" fill="none">
            <rect x="4" y="4" width="40" height="40" rx="12" fill="var(--accent-dim)" stroke="var(--accent)" strokeWidth="1.5" />
            <path d="M20 16L32 24L20 32V16Z" fill="var(--accent)" />
          </svg>
        </div>
        <h2 className="onboarding-title">最初のタスクを作成しましょう</h2>
        <p className="onboarding-desc">
          コマンドの定期実行をスケジュールできます。<br />
          バックアップ、デプロイ、ヘルスチェックなど、<br />
          繰り返し実行したいタスクを登録してみましょう。
        </p>
        <button className="btn btn-primary onboarding-cta" onClick={onCreate}>
          + 最初のタスクを作成
        </button>
      </div>
    </div>
  );
}

function OnboardingForm({ onSave }: { onSave: (task: TaskDefinition) => Promise<boolean> }) {
  return (
    <div className="onboarding-form-wrap">
      <TaskDetailPanel
        isNew
        onSave={onSave}
        onRun={() => {}}
        onStop={() => {}}
        onDelete={() => {}}
      />
    </div>
  );
}

// --- Main View ---

export function TasksView({ tasks, loading, onRun, onStop, onSave, onDelete }: Props) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [isNew, setIsNew] = useState(false);

  // タスクがあるのに未選択なら最初のタスクを自動選択
  const effectiveId = selectedId ?? (tasks.length > 0 && !isNew ? tasks[0]!.task.id : null);
  const selectedTask = isNew ? undefined : tasks.find((t) => t.task.id === effectiveId);

  // Clear selection if selected task was deleted
  useEffect(() => {
    if (selectedId && !isNew && !tasks.find((t) => t.task.id === selectedId)) {
      setSelectedId(null);
    }
  }, [tasks, selectedId, isNew]);

  // --- Loading ---
  if (loading) return null;

  // --- Empty state: no tasks ---
  if (tasks.length === 0 && !selectedId) {
    if (isNew) {
      return (
        <OnboardingForm
          onSave={async (task) => {
            const ok = await onSave(task);
            if (ok) {
              setSelectedId(task.id);
              setIsNew(false);
            }
            return ok;
          }}
        />
      );
    }
    return <EmptyState onCreate={() => setIsNew(true)} />;
  }

  // --- Normal master-detail ---
  return (
    <div className="master-detail">
      <div className="task-list-panel">
        <button
          className="btn btn-primary new-task-btn"
          onClick={() => { setIsNew(true); setSelectedId(null); }}
        >
          + 新規タスク
        </button>
        <div className="task-list">
          {tasks.map((t) => (
            <TaskListItem
              key={t.task.id}
              task={t}
              selected={t.task.id === effectiveId && !isNew}
              onSelect={() => { setSelectedId(t.task.id); setIsNew(false); }}
            />
          ))}
        </div>
      </div>

      <div className="task-detail-panel">
        {selectedTask || isNew ? (
          <TaskDetailPanel
            key={isNew ? "__new__" : effectiveId}
            task={selectedTask?.task}
            taskStatus={selectedTask}
            isNew={isNew}
            onSave={async (task) => {
              const ok = await onSave(task);
              if (ok && isNew) {
                setSelectedId(task.id);
                setIsNew(false);
              }
              return ok;
            }}
            onRun={() => effectiveId && onRun(effectiveId)}
            onStop={() => effectiveId && onStop(effectiveId)}
            onDelete={() => {
              if (selectedTask) {
                onDelete(selectedTask.task.id, selectedTask.task.name);
                setSelectedId(null);
              }
            }}
          />
        ) : null}
      </div>
    </div>
  );
}
