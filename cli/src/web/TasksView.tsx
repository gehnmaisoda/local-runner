import React, { useState, useEffect, useCallback, useRef, useMemo } from "react";
import type { TaskStatus, TaskDefinition, ExecutionRecord, Schedule } from "./types.ts";
import { formatDate, formatDuration, formatSchedule, statusIcon } from "./format.ts";
import { LogModal } from "./LogViewer.tsx";
import { useCountdown } from "./hooks.ts";

// --- Props ---

interface Props {
  tasks: TaskStatus[];
  loading: boolean;
  isNewTask: boolean;
  onNewTaskChange: (v: boolean) => void;
  onRun: (id: string) => void;
  onStop: (id: string) => void;
  onSave: (task: TaskDefinition) => Promise<boolean>;
  onDelete: (id: string, name: string) => void;
  slackConfigured: boolean;
}

// --- Shared components ---

function StatusDot({ task }: { task: TaskStatus }) {
  if (task.isRunning) return <span className="status-dot running" />;
  if (task.lastRun?.status === "failure") return <span className="status-dot failure" />;
  if (task.lastRun?.status === "timeout") return <span className="status-dot failure" />;
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

export function TriggerTag({ trigger }: { trigger?: ExecutionRecord["trigger"] }) {
  if (!trigger || trigger === "scheduled") return null;
  const label = trigger === "catchup" ? "キャッチアップ" : "手動実行";
  return <span className={`trigger-tag trigger-${trigger}`}>{label}</span>;
}

function LogRow({ record, onClick }: { record: ExecutionRecord; onClick: () => void }) {
  return (
    <div className="log-row" onClick={onClick}>
      <div className="log-row-header">
        <span className={`status-dot ${record.status}`} />
        <span className="log-row-time">{formatDate(record.startedAt)}</span>
        <StatusResult status={record.status} duration={formatDuration(record)} />
        <TriggerTag trigger={record.trigger} />
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

// --- Directory grouping ---

interface TaskGroup {
  dir: string;
  label: string;
  tasks: TaskStatus[];
}

/** /Users/username/... → ~/... */
export function resolveHome(dir: string): string {
  return dir.replace(/^\/Users\/[^/]+/, "~");
}

/** ~/a/b/c/d → c/d (4セグメント以上は末尾2つ、3つ以下はそのまま) */
export function shortenDir(dir: string): string {
  const resolved = resolveHome(dir);
  const parts = resolved.split("/").filter((p) => p !== "");
  if (parts.length <= 3) return resolved;
  return parts.slice(-2).join("/");
}

function groupByDirectory(tasks: TaskStatus[]): TaskGroup[] {
  const map = new Map<string, TaskStatus[]>();
  for (const t of tasks) {
    const dir = resolveHome(t.task.working_directory || "~");
    if (!map.has(dir)) map.set(dir, []);
    map.get(dir)!.push(t);
  }
  return Array.from(map, ([dir, tasks]) => ({ dir, label: shortenDir(dir), tasks }));
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

/** Validate a cron expression (5 fields, valid characters only). Returns null if valid, error message if invalid. */
export function validateCron(expr: string): string | null {
  const trimmed = expr.trim();
  if (!trimmed) return null; // empty is ok (will be caught by "required" logic elsewhere)
  const fields = trimmed.split(/\s+/);
  if (fields.length !== 5) {
    return `5つのフィールドが必要です（現在 ${fields.length} つ）`;
  }
  const validPattern = /^[0-9*\/,\-]+$/;
  const fieldNames = ["分", "時", "日", "月", "曜日"];
  for (let i = 0; i < fields.length; i++) {
    if (!validPattern.test(fields[i]!)) {
      return `${fieldNames[i]}フィールドに無効な文字が含まれています: "${fields[i]}"`;
    }
  }
  return null;
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

// --- Task Form Fields (shared between detail panel and new task modal) ---

interface TaskFormState {
  name: string; setName: (v: string) => void;
  command: string; setCommand: (v: string) => void;
  workingDirectory: string; setWorkingDirectory: (v: string) => void;
  dirError: string | null; setDirError: (v: string | null) => void;
  dirValidating: React.MutableRefObject<boolean>;
  catchUp: boolean; setCatchUp: (v: boolean) => void;
  slackNotify: boolean; setSlackNotify: (v: boolean) => void;
  slackMentions: string[]; setSlackMentions: (v: string[]) => void;
  timeout: number; setTimeout_: (v: number) => void;
  scheduleType: string; setScheduleType: (v: string) => void;
  hour: number; setHour: (v: number) => void;
  minute: number; setMinute: (v: number) => void;
  weekdays: number[]; toggleWeekday: (d: number) => void;
  monthDays: number[]; toggleMonthDay: (d: number) => void;
  cronExpr: string; setCronExpr: (v: string) => void;
}

function useTaskForm(task?: TaskDefinition): TaskFormState {
  const [name, setName] = useState(task?.name ?? "");
  const [command, setCommand] = useState(task?.command ?? "");
  const [workingDirectory, setWorkingDirectory] = useState(task?.working_directory ?? "");
  const [dirError, setDirError] = useState<string | null>(null);
  const dirValidating = useRef(false);
  const [catchUp, setCatchUp] = useState(task?.catch_up ?? true);
  const [slackNotify, setSlackNotify] = useState(task?.slack_notify ?? true);
  const [slackMentions, setSlackMentions] = useState<string[]>(task?.slack_mentions ?? []);
  const [timeout, setTimeout_] = useState(task?.timeout ?? 0);

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

  return {
    name, setName, command, setCommand,
    workingDirectory, setWorkingDirectory, dirError, setDirError, dirValidating,
    catchUp, setCatchUp, slackNotify, setSlackNotify, slackMentions, setSlackMentions, timeout, setTimeout_,
    scheduleType, setScheduleType, hour, setHour, minute, setMinute,
    weekdays, toggleWeekday, monthDays, toggleMonthDay, cronExpr, setCronExpr,
  };
}

function buildTaskObj(form: TaskFormState, id: string, enabled: boolean): TaskDefinition {
  return {
    id,
    name: form.name.trim(),
    command: form.command,
    working_directory: form.workingDirectory.trim() || undefined,
    schedule: buildSchedule(form.scheduleType, form.hour, form.minute, form.weekdays, form.monthDays, form.cronExpr),
    enabled,
    catch_up: form.catchUp,
    slack_notify: form.slackNotify,
    slack_mentions: form.slackMentions.length > 0 ? form.slackMentions : undefined,
    timeout: form.timeout > 0 ? form.timeout : undefined,
  };
}

function TaskFormFields({ form, slackConfigured }: { form: TaskFormState; slackConfigured: boolean }) {
  return (
    <>
      <div className="detail-section">
        <label className="detail-label">実行コマンド</label>
        <textarea
          className="form-textarea"
          value={form.command}
          onChange={(e) => form.setCommand(e.target.value)}
          placeholder="echo 'hello world'"
          rows={6}
          autoComplete="off"
          data-1p-ignore
        />
      </div>

      <div className="detail-section">
        <label className="detail-label">実行ディレクトリ</label>
        <input
          className={`form-input ${form.dirError ? "input-error" : ""}`}
          type="text"
          value={form.workingDirectory}
          onChange={(e) => { form.setWorkingDirectory(e.target.value); form.setDirError(null); }}
          autoComplete="off"
          data-1p-ignore
          onBlur={async () => {
            const trimmed = form.workingDirectory.trim();
            if (!trimmed) { form.setDirError(null); return; }
            form.dirValidating.current = true;
            try {
              const res = await fetch(`/api/check-dir?path=${encodeURIComponent(trimmed)}`);
              const data = await res.json();
              form.setDirError(data.exists ? null : "ディレクトリが存在しません");
            } catch {
              form.setDirError(null);
            } finally {
              form.dirValidating.current = false;
            }
          }}
          placeholder="~/projects/myapp"
        />
        {form.dirError && <div className="field-error">{form.dirError}</div>}
        <div className="field-hint-small">※ 省略時はホームディレクトリで実行されます</div>
      </div>

      <div className="detail-section">
        <label className="detail-label">実行スケジュール ({Intl.DateTimeFormat().resolvedOptions().timeZone})</label>
        <div className="sched">
          <div className="sched-pills">
            {SCHEDULE_TYPES.map((st) => (
              <button
                key={st.value}
                type="button"
                className={`sched-pill ${form.scheduleType === st.value ? "active" : ""}`}
                onClick={() => form.setScheduleType(st.value)}
              >
                {st.label}
              </button>
            ))}
          </div>

          {form.scheduleType === "every_minute" && (
            <div className="sched-hint">毎分実行されます</div>
          )}

          {form.scheduleType === "hourly" && (
            <div className="sched-sentence">
              毎時
              <div className="sched-time-box">
                <NumInput className="sched-time-m" min={0} max={59} value={form.minute} onChange={form.setMinute} />
              </div>
              分に実行
            </div>
          )}

          {form.scheduleType === "daily" && (
            <div className="sched-sentence">
              毎日
              <div className="sched-time-box">
                <NumInput className="sched-time-h" min={0} max={23} value={form.hour} onChange={form.setHour} />
                <span className="sched-time-sep">:</span>
                <NumInput className="sched-time-m" min={0} max={59} value={form.minute} onChange={form.setMinute} />
              </div>
              に実行
            </div>
          )}

          {form.scheduleType === "weekly" && (
            <>
              <div className="sched-weekdays">
                {WEEKDAYS.map((d) => (
                  <button
                    key={d.value}
                    type="button"
                    className={`weekday-pill ${form.weekdays.includes(d.value) ? "active" : ""}`}
                    onClick={() => form.toggleWeekday(d.value)}
                  >
                    {d.label}
                  </button>
                ))}
              </div>
              <div className="sched-sentence">
                <div className="sched-time-box">
                  <NumInput className="sched-time-h" min={0} max={23} value={form.hour} onChange={form.setHour} />
                  <span className="sched-time-sep">:</span>
                  <NumInput className="sched-time-m" min={0} max={59} value={form.minute} onChange={form.setMinute} />
                </div>
                に実行
              </div>
            </>
          )}

          {form.scheduleType === "monthly" && (
            <>
              <div className="sched-monthdays">
                {MONTH_DAYS.map((d) => (
                  <button
                    key={d}
                    type="button"
                    className={`monthday-pill ${form.monthDays.includes(d) ? "active" : ""}`}
                    onClick={() => form.toggleMonthDay(d)}
                  >
                    {d}
                  </button>
                ))}
                <button
                  type="button"
                  className={`monthday-pill last-day ${form.monthDays.includes(-1) ? "active" : ""}`}
                  onClick={() => form.toggleMonthDay(-1)}
                >
                  月末
                </button>
              </div>
              <div className="sched-sentence">
                <div className="sched-time-box">
                  <NumInput className="sched-time-h" min={0} max={23} value={form.hour} onChange={form.setHour} />
                  <span className="sched-time-sep">:</span>
                  <NumInput className="sched-time-m" min={0} max={59} value={form.minute} onChange={form.setMinute} />
                </div>
                に実行
              </div>
            </>
          )}

          {form.scheduleType === "cron" && (
            <>
              <input
                className="form-input sched-cron"
                type="text"
                value={form.cronExpr}
                onChange={(e) => form.setCronExpr(e.target.value)}
                placeholder="*/15 * * * *"
                autoComplete="off"
                data-1p-ignore
              />
              {validateCron(form.cronExpr) && (
                <div className="field-error">{validateCron(form.cronExpr)}</div>
              )}
            </>
          )}
        </div>
      </div>

      <div className="detail-section">
        <label className="detail-label">オプション</label>
        <div className="checkbox-group">
          <label className="checkbox-label">
            <input type="checkbox" checked={form.catchUp} onChange={(e) => form.setCatchUp(e.target.checked)} />
            キャッチアップ実行
            <span className="tooltip-wrap">
              <span className="tooltip-hint">?</span>
              <span className="tooltip-bubble">
                タスクは <strong>ネットワーク接続中</strong> かつ <strong>ディスプレイが開いている</strong> 場合のみ実行されます。スリープ中やオフライン時はスキップされます。
                <br /><br />
                ONにすると、復帰時にスキップされたスケジュールを検知し <strong>1回だけ</strong> キャッチアップ実行します。複数回分溜まっていても実行は1回です。
                <br /><br />
                OFFにすると、スキップされたスケジュールはそのまま破棄されます。
                <br /><br />
                例: 毎朝 08:00 のタスク → スリープ中にスキップ → 11:00 に復帰 → 即座に1回実行
              </span>
            </span>
          </label>
        </div>
        <div className="timeout-row">
          <label className="detail-label-inline">タイムアウト</label>
          <input
            className="form-input timeout-input"
            type="text"
            inputMode="numeric"
            value={form.timeout || ""}
            onChange={(e) => {
              const n = parseInt(e.target.value.replace(/[^0-9]/g, ""), 10);
              form.setTimeout_(n > 0 ? n : 0);
            }}
            placeholder="なし"
          />
          <span className="field-hint-inline">秒</span>
          <span className="tooltip-wrap">
            <span className="tooltip-hint">?</span>
            <span className="tooltip-bubble">
              設定するとデフォルトタイムアウトより優先されます。
            </span>
          </span>
        </div>
      </div>

      {slackConfigured && (
        <div className="detail-section">
          <label className="detail-label">Slack 通知</label>
          <div className="checkbox-group">
            <label className="checkbox-label">
              <input type="checkbox" checked={form.slackNotify} onChange={(e) => form.setSlackNotify(e.target.checked)} />
              タスク完了時に Slack に通知する
            </label>
            {form.slackNotify && (
              <>
                <label className="checkbox-label">
                  <input
                    type="checkbox"
                    checked={form.slackMentions.includes("<!channel>")}
                    onChange={(e) => {
                      if (e.target.checked) {
                        form.setSlackMentions([...form.slackMentions, "<!channel>"]);
                      } else {
                        form.setSlackMentions(form.slackMentions.filter(m => m !== "<!channel>"));
                      }
                    }}
                  />
                  @channel でメンション
                </label>
                <SlackUserMentions mentions={form.slackMentions} onChange={form.setSlackMentions} />
              </>
            )}
          </div>
        </div>
      )}
    </>
  );
}

// --- Slack User Mentions ---

interface SlackUser {
  id: string;
  name: string;
  real_name?: string;
  is_bot: boolean;
  deleted: boolean;
}

function SlackUserMentions({ mentions, onChange }: {
  mentions: string[];
  onChange: (v: string[]) => void;
}) {
  const [users, setUsers] = useState<SlackUser[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [adding, setAdding] = useState(false);

  const userMentions = mentions.filter(m => m.startsWith("<@") && m.endsWith(">"));
  const userIds = userMentions.map(m => m.slice(2, -1));

  const fetchUsers = useCallback(async () => {
    if (loaded) return;
    try {
      const res = await fetch("/api/slack/users");
      const data = await res.json();
      if (data.ok && data.members) {
        setUsers(
          (data.members as SlackUser[])
            .filter((u: SlackUser) => !u.is_bot && !u.deleted && u.id !== "USLACKBOT")
            .sort((a: SlackUser, b: SlackUser) => (a.real_name ?? a.name).localeCompare(b.real_name ?? b.name))
        );
      }
    } catch { /* ignore */ }
    setLoaded(true);
  }, [loaded]);

  const handleAdd = () => {
    setAdding(true);
    fetchUsers();
  };

  const handleSelect = (userId: string) => {
    if (!userIds.includes(userId)) {
      onChange([...mentions, `<@${userId}>`]);
    }
    setAdding(false);
  };

  const handleRemove = (userId: string) => {
    onChange(mentions.filter(m => m !== `<@${userId}>`));
  };

  return (
    <div className="slack-user-mentions">
      {userIds.map(uid => {
        const user = users.find(u => u.id === uid);
        return (
          <span key={uid} className="mention-chip">
            @{user ? (user.real_name ?? user.name) : uid}
            <button className="mention-chip-remove" onClick={() => handleRemove(uid)}>&times;</button>
          </span>
        );
      })}
      {adding ? (
        <select
          className="form-input mention-select"
          autoFocus
          onChange={(e) => { if (e.target.value) handleSelect(e.target.value); }}
          onBlur={() => setAdding(false)}
          defaultValue=""
        >
          <option value="">ユーザーを選択...</option>
          {users.filter(u => !userIds.includes(u.id)).map(u => (
            <option key={u.id} value={u.id}>
              {u.real_name ?? u.name}
            </option>
          ))}
        </select>
      ) : (
        <button className="btn-small" type="button" onClick={handleAdd}>+ ユーザーを追加</button>
      )}
    </div>
  );
}

// --- Detail Panel (editing existing tasks) ---

interface DetailProps {
  task: TaskDefinition;
  taskStatus: TaskStatus;
  onSave: (task: TaskDefinition) => Promise<boolean>;
  onRun: () => void;
  onStop: () => void;
  onDelete: () => void;
  slackConfigured: boolean;
}

const LOG_PAGE_SIZE = 15;

function TaskDetailPanel({ task, taskStatus, onSave, onRun, onStop, onDelete, slackConfigured }: DetailProps) {
  const countdown = useCountdown(taskStatus.nextRunAt);
  const form = useTaskForm(task);

  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved">("idle");

  // History
  const [history, setHistory] = useState<ExecutionRecord[]>([]);
  const [historyLimit, setHistoryLimit] = useState(LOG_PAGE_SIZE);
  const [hasMore, setHasMore] = useState(false);
  const [viewingLog, setViewingLog] = useState<ExecutionRecord | null>(null);

  const loadHistory = useCallback(async (limit: number) => {
    try {
      const res = await fetch(`/api/history?taskId=${task.id}&limit=${limit + 1}`);
      const data = await res.json();
      const records: ExecutionRecord[] = data.history ?? [];
      records.sort((a, b) => new Date(b.startedAt).getTime() - new Date(a.startedAt).getTime());
      setHasMore(records.length > limit);
      setHistory(records.slice(0, limit));
    } catch { /* ignore */ }
  }, [task.id]);

  useEffect(() => {
    loadHistory(historyLimit);
  }, [loadHistory, historyLimit, taskStatus.lastRun?.id, taskStatus.isRunning]);

  const handleLoadMore = () => {
    setHistoryLimit((prev) => prev + LOG_PAGE_SIZE);
  };

  // --- Auto-save ---
  const onSaveRef = useRef(onSave);
  useEffect(() => { onSaveRef.current = onSave; });
  const isFirstRender = useRef(true);

  useEffect(() => {
    if (isFirstRender.current) { isFirstRender.current = false; return; }
    if (!form.name.trim() || !form.command || form.dirValidating.current) { setSaveStatus("idle"); return; }

    setSaveStatus("idle");
    const taskObj = buildTaskObj(form, task.id, task.enabled);

    const timer = setTimeout(async () => {
      setSaveStatus("saving");
      const ok = await onSaveRef.current(taskObj);
      setSaveStatus(ok ? "saved" : "idle");
    }, 600);

    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [task.id, form.name, form.command, form.workingDirectory, form.scheduleType, form.hour, form.minute, JSON.stringify(form.weekdays), JSON.stringify(form.monthDays), form.cronExpr, form.catchUp, form.slackNotify, JSON.stringify(form.slackMentions), form.timeout]);

  return (
    <div className="detail-panel">
      <div className="detail-header">
        <input
          className="detail-name-input"
          type="text"
          value={form.name}
          onChange={(e) => form.setName(e.target.value)}
          placeholder="タスク名"
          autoComplete="off"
          data-1p-ignore
        />
        <div className="detail-header-actions">
          <span className={`save-status ${saveStatus}`}>
            {saveStatus === "saving" ? "保存中..." : saveStatus === "saved" ? "\u2713" : ""}
          </span>
          {taskStatus.isRunning ? (
            <button className="btn btn-stop" onClick={onStop}><StopIcon />停止</button>
          ) : (
            <button className="btn btn-run" onClick={onRun}><PlayIcon />実行</button>
          )}
        </div>
      </div>

      <div className="detail-body two-col">
        <div className="detail-col-form">
          <TaskFormFields form={form} slackConfigured={slackConfigured} />
          <div className="detail-section detail-delete">
            <button className="btn btn-danger-ghost" onClick={onDelete}>
              <TrashIcon />タスクを削除
            </button>
          </div>
        </div>

        <div className="detail-col-log">
          {taskStatus.nextRunAt && (
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
      </div>

      {viewingLog && (
        <LogModal record={viewingLog} onClose={() => setViewingLog(null)} />
      )}
    </div>
  );
}

// --- New Task Modal ---

function NewTaskModal({ onSave, onClose, slackConfigured }: {
  onSave: (task: TaskDefinition) => Promise<boolean>;
  onClose: () => void;
  slackConfigured: boolean;
}) {
  const [autoId] = useState(() => generateId());
  const form = useTaskForm();
  const [creating, setCreating] = useState(false);

  const hasContent = form.name.trim() !== "" || form.command !== "";
  const canCreate = form.name.trim() !== "" && form.command !== "";

  // モーダル表示中は背後のスクロールを無効化
  useEffect(() => {
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = ""; };
  }, []);

  const handleClose = () => {
    if (hasContent && !confirm("入力内容が保存されていません。\n入力内容が消えますが、よろしいですか？")) return;
    onClose();
  };

  const handleCreate = async () => {
    setCreating(true);
    const ok = await onSave(buildTaskObj(form, autoId, true));
    setCreating(false);
    if (ok) onClose();
  };

  const handleCloseRef = useRef(handleClose);
  handleCloseRef.current = handleClose;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") handleCloseRef.current(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="modal-overlay" onClick={handleClose}>
      <div className="modal modal-new-task" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>新規タスク</h2>
          <button className="modal-close" onClick={handleClose}>&times;</button>
        </div>
        <div className="modal-body">
          <div className="detail-section">
            <label className="detail-label">タスク名</label>
            <input
              className="form-input"
              type="text"
              value={form.name}
              onChange={(e) => form.setName(e.target.value)}
              placeholder="タスク名"
              autoFocus
              autoComplete="off"
              data-1p-ignore
            />
          </div>
          <TaskFormFields form={form} slackConfigured={slackConfigured} />
        </div>
        <div className="modal-footer">
          <button
            className="btn btn-primary"
            onClick={handleCreate}
            disabled={creating || !canCreate}
          >
            作成
          </button>
        </div>
      </div>
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
          エージェントの定期実行、毎日の情報収集など、<br />
          自動化したいタスクを登録してみましょう。
        </p>
        <button className="btn btn-primary onboarding-cta" onClick={onCreate}>
          + 最初のタスクを作成
        </button>
      </div>
    </div>
  );
}

// --- Main View ---

export function TasksView({ tasks, loading, isNewTask, onNewTaskChange, onRun, onStop, onSave, onDelete, slackConfigured }: Props) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const groups = useMemo(() => groupByDirectory(tasks), [tasks]);

  // タスクがあるのに未選択なら最初のタスクを自動選択
  const effectiveId = selectedId ?? (tasks.length > 0 ? tasks[0]!.task.id : null);
  const selectedTask = effectiveId ? tasks.find((t) => t.task.id === effectiveId) : undefined;

  // Clear selection if selected task was deleted
  useEffect(() => {
    if (selectedId && !tasks.find((t) => t.task.id === selectedId)) {
      setSelectedId(null);
    }
  }, [tasks, selectedId]);

  // --- Loading ---
  if (loading) return null;

  // --- Empty state: no tasks ---
  if (tasks.length === 0) {
    return (
      <>
        <EmptyState onCreate={() => onNewTaskChange(true)} />
        {isNewTask && (
          <NewTaskModal
            onSave={onSave}
            onClose={() => onNewTaskChange(false)}
            slackConfigured={slackConfigured}
          />
        )}
      </>
    );
  }

  // --- Normal master-detail ---
  return (
    <>
      <div className="master-detail">
        <div className="task-list-panel">
          <div className="task-list">
            {groups.map((group) => (
              <div key={group.dir} className="task-group">
                <div className="task-group-header" title={group.dir}>{group.label}</div>
                {group.tasks.map((t) => (
                  <TaskListItem
                    key={t.task.id}
                    task={t}
                    selected={t.task.id === effectiveId}
                    onSelect={() => setSelectedId(t.task.id)}
                  />
                ))}
              </div>
            ))}
          </div>
        </div>

        <div className="task-detail-panel">
          {selectedTask && (
            <TaskDetailPanel
              key={effectiveId}
              task={selectedTask.task}
              taskStatus={selectedTask}
              onSave={onSave}
              onRun={() => onRun(selectedTask.task.id)}
              onStop={() => onStop(selectedTask.task.id)}
              onDelete={() => {
                onDelete(selectedTask.task.id, selectedTask.task.name);
                setSelectedId(null);
              }}
              slackConfigured={slackConfigured}
            />
          )}
        </div>
      </div>

      {isNewTask && (
        <NewTaskModal
          onSave={onSave}
          onClose={() => onNewTaskChange(false)}
          slackConfigured={slackConfigured}
        />
      )}
    </>
  );
}
