import React, { useEffect } from "react";
import type { ExecutionRecord } from "./types.ts";
import { formatDate, formatDuration } from "./format.ts";

interface ModalProps {
  record: ExecutionRecord;
  onClose: () => void;
}

function statusLabel(status: ExecutionRecord["status"]): string {
  switch (status) {
    case "success": return "Success";
    case "failure": return "Failed";
    case "stopped": return "Stopped";
    case "running": return "Running";
  }
}

function mergeOutput(record: ExecutionRecord): string {
  const parts: string[] = [];
  if (record.stdout.trim()) parts.push(record.stdout.trimEnd());
  if (record.stderr.trim()) parts.push(record.stderr.trimEnd());
  return parts.join("\n");
}

export function LogModal({ record, onClose }: ModalProps) {
  const output = mergeOutput(record);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="modal modal-log">
        <div className="modal-header">
          <div className="log-modal-title">
            <h2>{record.taskName}</h2>
            <div className="log-meta">
              <span className={`log-status-badge ${record.status}`}>
                {statusLabel(record.status)}
              </span>
              <span className="log-meta-item">{formatDate(record.startedAt)}</span>
              <span className="log-meta-item">{formatDuration(record)}</span>
            </div>
          </div>
          <button className="modal-close" onClick={onClose}>&times;</button>
        </div>
        <div className="log-modal-body">
          {output ? (
            <pre className="log-pre">{output}</pre>
          ) : (
            <div className="log-empty">No output</div>
          )}
        </div>
      </div>
    </div>
  );
}

interface CompactLogProps {
  record: ExecutionRecord;
  onClick?: () => void;
}

export function CompactLogRow({ record, onClick }: CompactLogProps) {
  return (
    <div className="compact-log-row" onClick={onClick}>
      <span className={`status-dot ${record.status}`} />
      <span className="compact-log-time">{formatDate(record.startedAt)}</span>
      <span className="compact-log-duration">{formatDuration(record)}</span>
      {record.status === "stopped" ? (
        <span className="compact-log-stopped">Stopped</span>
      ) : record.exitCode != null && record.exitCode !== 0 ? (
        <span className="compact-log-exit">exit {record.exitCode}</span>
      ) : null}
    </div>
  );
}
