import React, { useState, useEffect, useRef, useCallback } from "react";
import type { GlobalSettings, LogEntry } from "./types.ts";

interface Props {
  settings: GlobalSettings | null;
  loading: boolean;
  onSave: (settings: GlobalSettings) => Promise<boolean>;
}

interface SlackChannel {
  id: string;
  name: string;
  is_private: boolean;
}

// GlobalSettings.defaultTimeoutValue (Swift側) と同期させること
const DEFAULT_TIMEOUT = 3600;

export function SettingsView({ settings, loading, onSave }: Props) {
  const [botToken, setBotToken] = useState("");
  const [slackChannel, setSlackChannel] = useState("");
  const [defaultTimeout, setDefaultTimeout] = useState(DEFAULT_TIMEOUT);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved">("idle");
  const [showSystemLog, setShowSystemLog] = useState(false);

  // Slack channel picker
  const [channels, setChannels] = useState<SlackChannel[]>([]);
  const [channelsLoading, setChannelsLoading] = useState(false);
  const [channelsError, setChannelsError] = useState<string | null>(null);

  // Test send
  const [testStatus, setTestStatus] = useState<"idle" | "sending" | "ok" | "error">("idle");
  const [testError, setTestError] = useState<string | null>(null);

  const initialized = useRef(false);

  useEffect(() => {
    if (!settings || initialized.current) return;
    initialized.current = true;
    setBotToken(settings.slack_bot_token ?? "");
    setSlackChannel(settings.slack_channel ?? "");
    setDefaultTimeout(settings.default_timeout ?? DEFAULT_TIMEOUT);
    // トークンが設定済みならチャンネル一覧を取得
    if (settings.slack_bot_token?.startsWith("xoxb-")) {
      fetchChannels();
    }
  }, [settings, fetchChannels]);

  // チャンネル一覧を取得（サーバーが保存済みトークンを使用）
  const fetchChannels = useCallback(async () => {
    setChannelsLoading(true);
    setChannelsError(null);
    try {
      const res = await fetch("/api/slack/channels");
      const data = await res.json();
      if (data.ok && data.channels) {
        const sorted = (data.channels as SlackChannel[])
          .sort((a: SlackChannel, b: SlackChannel) => a.name.localeCompare(b.name));
        setChannels(sorted);
      } else {
        setChannelsError(data.error ?? "チャンネルの取得に失敗しました");
        setChannels([]);
      }
    } catch {
      setChannelsError("チャンネルの取得に失敗しました");
      setChannels([]);
    } finally {
      setChannelsLoading(false);
    }
  }, []);

  // Auto-save on change (debounced)
  const onSaveRef = useRef(onSave);
  useEffect(() => { onSaveRef.current = onSave; });
  const isFirstRender = useRef(true);

  useEffect(() => {
    if (!initialized.current) return;
    if (isFirstRender.current) { isFirstRender.current = false; return; }

    setSaveStatus("idle");
    const timer = setTimeout(async () => {
      setSaveStatus("saving");
      const ok = await onSaveRef.current({
        slack_bot_token: botToken.trim() || undefined,
        slack_channel: slackChannel || undefined,
        default_timeout: defaultTimeout > 0 ? defaultTimeout : undefined,
      });
      setSaveStatus(ok ? "saved" : "idle");
      // トークン保存後にチャンネル一覧を取得（needsFetchChannels フラグで制御）
      if (ok && needsFetchChannelsRef.current) {
        needsFetchChannelsRef.current = false;
        fetchChannels();
      }
    }, 600);

    return () => clearTimeout(timer);
  }, [botToken, slackChannel, defaultTimeout, fetchChannels]);

  // トークンが変わったらフラグを立てる（実際の取得は auto-save 完了後）
  const needsFetchChannelsRef = useRef(false);
  const prevTokenRef = useRef(botToken);
  useEffect(() => {
    if (!initialized.current) return;
    if (botToken !== prevTokenRef.current) {
      prevTokenRef.current = botToken;
      if (botToken.startsWith("xoxb-")) {
        needsFetchChannelsRef.current = true;
      } else {
        setChannels([]);
      }
    }
  }, [botToken]);

  const handleTestSend = async () => {
    if (!botToken || !slackChannel) return;
    setTestStatus("sending");
    setTestError(null);
    try {
      const res = await fetch("/api/slack/test", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ channel: slackChannel }),
      });
      const data = await res.json();
      if (data.ok) {
        setTestStatus("ok");
        setTimeout(() => setTestStatus("idle"), 3000);
      } else {
        setTestStatus("error");
        setTestError(data.error ?? "送信に失敗しました");
      }
    } catch {
      setTestStatus("error");
      setTestError("送信に失敗しました");
    }
  };

  if (loading) return null;

  const channelName = channels.find(c => c.id === slackChannel)?.name;

  return (
    <div className="settings-view">
      <div className="settings-card">
        <div className="settings-header">
          <h2 className="settings-title">設定</h2>
          <span className={`save-status ${saveStatus}`}>
            {saveStatus === "saving" ? "保存中..." : saveStatus === "saved" ? "\u2713" : ""}
          </span>
        </div>

        <div className="settings-section">
          <h3 className="settings-section-title">全般</h3>
          <div className="settings-field">
            <label className="settings-label">デフォルトタイムアウト</label>
            <div className="settings-field-row">
              <input
                className="form-input settings-timeout-input"
                type="text"
                inputMode="numeric"
                value={defaultTimeout || ""}
                onChange={(e) => {
                  const n = parseInt(e.target.value.replace(/[^0-9]/g, ""), 10);
                  setDefaultTimeout(n > 0 ? n : 0);
                }}
                placeholder={String(DEFAULT_TIMEOUT)}
              />
              <span className="field-hint-inline">秒</span>
            </div>
            <div className="field-hint-small">
              タスクごとのタイムアウトが設定されている場合はそちらが優先されます。
              デフォルト: {DEFAULT_TIMEOUT} 秒（1時間）
            </div>
          </div>
        </div>

        <div className="settings-section">
          <h3 className="settings-section-title">Slack 通知</h3>
          <div className="settings-field">
            <label className="settings-label">Bot Token</label>
            <input
              className="form-input"
              type="password"
              value={botToken}
              onChange={(e) => setBotToken(e.target.value)}
              placeholder="xoxb-..."
              autoComplete="off"
              data-1p-ignore
            />
            <div className="field-hint-small">
              Slack App の Bot User OAuth Token を入力してください。
              必要なスコープ: <code>chat:write</code>, <code>channels:read</code>, <code>users:read</code>
            </div>
          </div>
          <div className="settings-field">
            <label className="settings-label">通知先チャンネル</label>
            {channelsLoading ? (
              <div className="field-hint-small">チャンネルを取得中...</div>
            ) : channelsError ? (
              <>
                <input
                  className="form-input"
                  type="text"
                  value={slackChannel}
                  onChange={(e) => setSlackChannel(e.target.value)}
                  placeholder="C1234567890"
                  autoComplete="off"
                  data-1p-ignore
                />
                <div className="field-error">{channelsError}</div>
              </>
            ) : channels.length > 0 ? (
              <select
                className="form-input"
                value={slackChannel}
                onChange={(e) => setSlackChannel(e.target.value)}
              >
                <option value="">チャンネルを選択...</option>
                {channels.map((ch) => (
                  <option key={ch.id} value={ch.id}>#{ch.name}</option>
                ))}
              </select>
            ) : (
              <input
                className="form-input"
                type="text"
                value={slackChannel}
                onChange={(e) => setSlackChannel(e.target.value)}
                placeholder="C1234567890"
                autoComplete="off"
                data-1p-ignore
              />
            )}
            {slackChannel && channelName && (
              <div className="field-hint-small">#{channelName} ({slackChannel})</div>
            )}
          </div>
          {botToken && slackChannel && (
            <div className="settings-field">
              <button
                className="btn-small"
                onClick={handleTestSend}
                disabled={testStatus === "sending"}
              >
                {testStatus === "sending" ? "送信中..." : testStatus === "ok" ? "\u2713 送信成功" : "テスト送信"}
              </button>
              {testStatus === "error" && testError && (
                <div className="field-error">{testError}</div>
              )}
            </div>
          )}
        </div>

        <div className="settings-section">
          <h3 className="settings-section-title">デバッグ</h3>
          <div className="settings-field">
            <button className="btn-small" onClick={() => setShowSystemLog(true)}>
              システムログを表示
            </button>
          </div>
        </div>
      </div>
      {showSystemLog && <SystemLogModal onClose={() => setShowSystemLog(false)} />}
    </div>
  );
}

// --- System Log Modal ---

function SystemLogModal({ onClose }: { onClose: () => void }) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [loading, setLoading] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  const fetchLogs = async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/system-logs?limit=1000");
      const data = await res.json();
      if (data.systemLogs) setLogs(data.systemLogs);
    } catch { /* ignore */ }
    setLoading(false);
  };

  const clearLogs = async () => {
    if (!confirm("システムログを削除しますか？")) return;
    try {
      await fetch("/api/system-logs", { method: "DELETE" });
      setLogs([]);
    } catch { /* ignore */ }
  };

  useEffect(() => { fetchLogs(); }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [logs]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prev;
    };
  }, [onClose]);

  const formatTimestamp = (ts: string) => {
    const d = new Date(ts);
    const pad = (n: number) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  };

  return (
    <div className="modal-overlay" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="modal modal-system-log">
        <div className="modal-header">
          <h2>システムログ</h2>
          <div className="system-log-modal-actions">
            <button className="btn-small btn-danger" onClick={clearLogs} disabled={logs.length === 0}>
              削除
            </button>
            <button className="btn-small" onClick={fetchLogs} disabled={loading}>
              {loading ? "..." : "更新"}
            </button>
            <button className="modal-close" onClick={onClose}>&times;</button>
          </div>
        </div>
        <div className="system-log-container">
          {logs.length === 0 ? (
            <div className="system-log-empty">ログがありません</div>
          ) : (
            logs.map((entry, i) => (
              <div className="system-log-line" key={i}>
                <span className="system-log-time">{formatTimestamp(entry.timestamp)}</span>
                <span className={`system-log-tag system-log-tag-${entry.tag.toLowerCase()}`}>{entry.tag}</span>
                <span className="system-log-message">{entry.message}</span>
              </div>
            ))
          )}
          <div ref={bottomRef} />
        </div>
      </div>
    </div>
  );
}
