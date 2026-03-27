import React, { useState } from "react";
import type { ExecutionRecord } from "./types.ts";
import { formatDate, formatDuration } from "./format.ts";
import { LogModal } from "./LogViewer.tsx";
import { StatusResult } from "./TasksView.tsx";

interface Props {
  history: ExecutionRecord[];
}

export function TimelineView({ history }: Props) {
  const [viewingLog, setViewingLog] = useState<ExecutionRecord | null>(null);

  if (history.length === 0) {
    return <div className="empty">実行履歴がまだありません。</div>;
  }

  return (
    <>
      <div className="timeline-list">
        {history.map((r) => (
          <div key={r.id} className="timeline-entry" onClick={() => setViewingLog(r)}>
            <div className="timeline-entry-header">
              <span className={`status-dot ${r.status}`} />
              <span className="timeline-task-name">{r.taskName}</span>
              <span className="timeline-right">
                <span className="timeline-time">{formatDate(r.startedAt)}</span>
                <StatusResult status={r.status} duration={formatDuration(r)} />
              </span>
            </div>
          </div>
        ))}
      </div>

      {viewingLog && (
        <LogModal record={viewingLog} onClose={() => setViewingLog(null)} />
      )}
    </>
  );
}
