export interface TaskDefinition {
  id: string;
  name: string;
  description?: string;
  command: string;
  working_directory?: string;
  schedule: Schedule;
  enabled: boolean;
  catch_up: boolean;
  notify_on_failure: boolean;
}

export interface Schedule {
  type: string;
  minute?: number;      // hourly: 0-59
  time?: string;        // daily/weekly: "HH:mm"
  weekday?: number;     // weekly: 1=Mon...7=Sun (ISO)
  expression?: string;  // cron
}

export interface ExecutionRecord {
  id: string;
  taskId: string;
  taskName: string;
  startedAt: string;
  finishedAt?: string;
  exitCode?: number;
  stdout: string;
  stderr: string;
  status: "running" | "success" | "failure" | "stopped";
}

export interface TaskStatus {
  task: TaskDefinition;
  lastRun?: ExecutionRecord;
  nextRunAt?: string;
  isRunning: boolean;
}
