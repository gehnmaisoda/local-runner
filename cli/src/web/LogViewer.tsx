import React, { useEffect, useState } from "react";
import type { ExecutionRecord } from "./types.ts";
import { formatDate, formatDuration, statusLabel } from "./format.ts";

interface ModalProps {
  record: ExecutionRecord;
  onClose: () => void;
}

function mergeOutput(record: ExecutionRecord): string {
  const parts: string[] = [];
  if (record.stdout.trim()) parts.push(record.stdout.trimEnd());
  if (record.stderr.trim()) parts.push(record.stderr.trimEnd());
  return parts.join("\n");
}

const COMMAND_PREVIEW_LEN = 30;

export function LogModal({ record, onClose }: ModalProps) {
  const output = mergeOutput(record);
  const [showFullCommand, setShowFullCommand] = useState(false);

  const commandLong = record.command.length > COMMAND_PREVIEW_LEN;
  const commandPreview = commandLong && !showFullCommand
    ? record.command.slice(0, COMMAND_PREVIEW_LEN) + "..."
    : record.command;

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
    };
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
            <div className="log-context">
              {record.command && (
                <div className="log-context-row">
                  <span className="log-context-label">コマンド</span>
                  <code className="log-context-value">{commandPreview}</code>
                  {commandLong && (
                    <button
                      className="log-context-toggle"
                      onClick={() => setShowFullCommand(!showFullCommand)}
                    >
                      {showFullCommand ? "省略" : "全文表示"}
                    </button>
                  )}
                </div>
              )}
              {record.working_directory && (
                <div className="log-context-row">
                  <span className="log-context-label">ディレクトリ</span>
                  <code className="log-context-value">{record.working_directory}</code>
                </div>
              )}
            </div>
          </div>
          <button className="modal-close" onClick={onClose}>&times;</button>
        </div>
        <div className="log-modal-body">
          {output ? (
            <pre className="log-pre">{output}</pre>
          ) : (
            <div className="log-empty">出力なし</div>
          )}
        </div>
      </div>
    </div>
  );
}
