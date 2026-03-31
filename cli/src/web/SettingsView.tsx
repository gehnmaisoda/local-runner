import React, { useState, useEffect, useRef } from "react";
import type { GlobalSettings } from "./types.ts";

interface Props {
  settings: GlobalSettings | null;
  loading: boolean;
  onSave: (settings: GlobalSettings) => Promise<boolean>;
}

// GlobalSettings.defaultTimeoutValue (Swift側) と同期させること
const DEFAULT_TIMEOUT = 3600;

export function SettingsView({ settings, loading, onSave }: Props) {
  const [webhookURL, setWebhookURL] = useState("");
  const [defaultTimeout, setDefaultTimeout] = useState(DEFAULT_TIMEOUT);
  const [saveStatus, setSaveStatus] = useState<"idle" | "saving" | "saved">("idle");

  const initialized = useRef(false);

  useEffect(() => {
    if (!settings || initialized.current) return;
    initialized.current = true;
    setWebhookURL(settings.slack_webhook_url ?? "");
    setDefaultTimeout(settings.default_timeout ?? DEFAULT_TIMEOUT);
  }, [settings]);

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
        slack_webhook_url: webhookURL.trim() || undefined,
        default_timeout: defaultTimeout > 0 ? defaultTimeout : undefined,
      });
      setSaveStatus(ok ? "saved" : "idle");
    }, 600);

    return () => clearTimeout(timer);
  }, [webhookURL, defaultTimeout]);

  if (loading) return null;

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
            <label className="settings-label">Webhook URL</label>
            <input
              className="form-input"
              type="text"
              value={webhookURL}
              onChange={(e) => setWebhookURL(e.target.value)}
              placeholder="https://hooks.slack.com/services/..."
            />
            <div className="field-hint-small">
              タスクの「失敗時に通知」が有効な場合、失敗・タイムアウト時にこの Webhook に通知が送信されます。
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
