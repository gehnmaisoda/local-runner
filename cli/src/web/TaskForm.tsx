import React, { useState, useEffect } from "react";
import type { TaskDefinition, Schedule } from "./types.ts";

interface Props {
  initial?: TaskDefinition;
  onSave: (task: TaskDefinition) => void;
  onCancel: () => void;
}

const SCHEDULE_TYPES = [
  { value: "every_minute", label: "Every minute" },
  { value: "hourly", label: "Hourly" },
  { value: "daily", label: "Daily" },
  { value: "weekly", label: "Weekly" },
  { value: "cron", label: "Cron expression" },
] as const;

// ISO weekday: 1=Mon...7=Sun
const WEEKDAYS = [
  { value: 1, label: "Mon" },
  { value: 2, label: "Tue" },
  { value: 3, label: "Wed" },
  { value: 4, label: "Thu" },
  { value: 5, label: "Fri" },
  { value: 6, label: "Sat" },
  { value: 7, label: "Sun" },
];

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

function formatTime(hour: number, minute: number): string {
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

export function TaskFormModal({ initial, onSave, onCancel }: Props) {
  const isEdit = !!initial;
  const [autoId] = useState(() => generateId());

  const [name, setName] = useState(initial?.name ?? "");
  const [command, setCommand] = useState(initial?.command ?? "");
  const [workingDirectory, setWorkingDirectory] = useState(initial?.working_directory ?? "");
  const [enabled, setEnabled] = useState(initial?.enabled ?? true);
  const [catchUp, setCatchUp] = useState(initial?.catch_up ?? true);
  const [notifyOnFailure, setNotifyOnFailure] = useState(initial?.notify_on_failure ?? false);

  const [scheduleType, setScheduleType] = useState(initial?.schedule.type ?? "daily");
  const initialTime = parseTime(initial?.schedule.time);
  const [hour, setHour] = useState(initialTime.hour || 9);
  const [minute, setMinute] = useState(initial?.schedule.type === "hourly" ? (initial?.schedule.minute ?? 0) : initialTime.minute);
  const [weekday, setWeekday] = useState(initial?.schedule.weekday ?? 1);
  const [cronExpr, setCronExpr] = useState(initial?.schedule.expression ?? "");

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onCancel();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onCancel]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();

    const schedule: Schedule = { type: scheduleType };
    if (scheduleType === "hourly") {
      schedule.minute = minute;
    } else if (scheduleType === "daily") {
      schedule.time = formatTime(hour, minute);
    } else if (scheduleType === "weekly") {
      schedule.time = formatTime(hour, minute);
      schedule.weekday = weekday;
    } else if (scheduleType === "cron") {
      schedule.expression = cronExpr;
    }

    const id = isEdit ? initial!.id : autoId;

    onSave({
      id,
      name: name.trim(),
      command,
      working_directory: workingDirectory.trim() || undefined,
      schedule,
      enabled,
      catch_up: catchUp,
      notify_on_failure: notifyOnFailure,
    });
  };

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onCancel(); }}>
      <div className="modal modal-wide">
        <div className="modal-header">
          <h2>{isEdit ? "Edit Task" : "New Task"}</h2>
          <button className="modal-close" onClick={onCancel}>&times;</button>
        </div>

        <form className="modal-body" onSubmit={handleSubmit}>
          <div className="form-grid">
            {/* Left column */}
            <div className="form-col">
              <div className="form-group">
                <label className="form-label">Name</label>
                <input
                  className="form-input"
                  type="text"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="My Task"
                  required
                  autoFocus
                />
              </div>

              <div className="form-group">
                <label className="form-label">Command</label>
                <textarea
                  className="form-textarea"
                  value={command}
                  onChange={(e) => setCommand(e.target.value)}
                  placeholder="echo 'hello world'"
                  required
                  rows={4}
                />
              </div>

              <div className="form-group">
                <label className="form-label">Working Directory</label>
                <input
                  className="form-input"
                  type="text"
                  value={workingDirectory}
                  onChange={(e) => setWorkingDirectory(e.target.value)}
                  placeholder="~/projects/my-app"
                />
              </div>
            </div>

            {/* Right column */}
            <div className="form-col">
              <div className="form-section">
                <div className="form-section-title">Schedule</div>
                <div className="form-group">
                  <select
                    className="form-select"
                    value={scheduleType}
                    onChange={(e) => setScheduleType(e.target.value)}
                  >
                    {SCHEDULE_TYPES.map((st) => (
                      <option key={st.value} value={st.value}>{st.label}</option>
                    ))}
                  </select>
                </div>

                {(scheduleType === "hourly" || scheduleType === "daily" || scheduleType === "weekly") && (
                  <div className="form-row">
                    {(scheduleType === "daily" || scheduleType === "weekly") && (
                      <div className="form-group">
                        <label className="form-label">Hour</label>
                        <input
                          className="form-input"
                          type="number"
                          min={0}
                          max={23}
                          value={hour}
                          onChange={(e) => setHour(+e.target.value)}
                        />
                      </div>
                    )}
                    <div className="form-group">
                      <label className="form-label">Minute</label>
                      <input
                        className="form-input"
                        type="number"
                        min={0}
                        max={59}
                        value={minute}
                        onChange={(e) => setMinute(+e.target.value)}
                      />
                    </div>
                    {scheduleType === "weekly" && (
                      <div className="form-group">
                        <label className="form-label">Weekday</label>
                        <select
                          className="form-select"
                          value={weekday}
                          onChange={(e) => setWeekday(+e.target.value)}
                        >
                          {WEEKDAYS.map((d) => (
                            <option key={d.value} value={d.value}>{d.label}</option>
                          ))}
                        </select>
                      </div>
                    )}
                  </div>
                )}

                {scheduleType === "cron" && (
                  <div className="form-group">
                    <label className="form-label">Expression</label>
                    <input
                      className="form-input"
                      type="text"
                      value={cronExpr}
                      onChange={(e) => setCronExpr(e.target.value)}
                      placeholder="*/15 * * * *"
                      required
                      style={{ fontFamily: "var(--font-mono)" }}
                    />
                  </div>
                )}
              </div>

              <div className="form-section">
                <div className="form-section-title">Options</div>
                <div className="checkbox-group">
                  <label className="checkbox-label">
                    <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
                    Enabled
                  </label>
                  <label className="checkbox-label">
                    <input type="checkbox" checked={catchUp} onChange={(e) => setCatchUp(e.target.checked)} />
                    Catch up after sleep
                  </label>
                  <label className="checkbox-label">
                    <input type="checkbox" checked={notifyOnFailure} onChange={(e) => setNotifyOnFailure(e.target.checked)} />
                    Notify on failure (Slack)
                  </label>
                </div>
              </div>
            </div>
          </div>

          <div className="form-footer">
            <button type="button" className="btn" onClick={onCancel}>
              Cancel
            </button>
            <button type="submit" className="btn btn-primary">
              {isEdit ? "Save Changes" : "Create Task"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
