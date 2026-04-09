export interface TaskDefinition {
  id: string;
  name: string;
  description?: string;
  command: string;
  working_directory?: string;
  schedule: Schedule;
  enabled: boolean;
  catch_up: boolean;
  slack_notify: boolean;
  slack_mentions?: string[];
  timeout?: number;
}

export interface Schedule {
  type: string;
  minute?: number;        // hourly: 0-59
  time?: string;          // daily/weekly/monthly: "HH:mm"
  weekday?: number;       // weekly (レガシー単体): 1=Mon...7=Sun (ISO)
  weekdays?: number[];    // weekly (マルチセレクト): [1,3,5]
  month_days?: number[];  // monthly: 日付リスト (-1 = 月末)
  expression?: string;    // cron
}

export interface ExecutionRecord {
  id: string;
  taskId: string;
  taskName: string;
  command: string;
  working_directory: string;
  startedAt: string;
  finishedAt?: string;
  exitCode?: number;
  stdout: string;
  stderr: string;
  status: "running" | "success" | "failure" | "stopped" | "timeout" | "pending";
  trigger?: "scheduled" | "catchup" | "manual";
}

export interface TaskStatus {
  task: TaskDefinition;
  lastRun?: ExecutionRecord;
  nextRunAt?: string;
  isRunning: boolean;
}

export interface GlobalSettings {
  slack_bot_token?: string;
  slack_channel?: string;
  slack_channel_name?: string;
  default_timeout?: number;
}

export interface LogEntry {
  timestamp: string;
  tag: string;
  message: string;
}
