import Foundation
import Yams
import Core

/// タスクのスケジューリングと実行を管理する。
final class TaskScheduler: @unchecked Sendable {
    private let taskStore: TaskStore
    private let logStore: LogStore
    private let executor = TaskExecutor()
    private let slackNotifier = SlackNotifier()

    private var tasks: [TaskDefinition] = []
    private var nextFireDates: [String: Date] = [:]

    private var timer: Timer?
    private var fileWatchTimer: Timer?
    private var lastDirModDate: Date = .distantPast
    private let lock = NSLock()

    /// IPC通知用コールバック
    var onNotification: ((IPCNotification) -> Void)?

    init(taskStore: TaskStore, logStore: LogStore) {
        self.taskStore = taskStore
        self.logStore = logStore
    }

    // MARK: - 起動・停止

    func start() {
        reloadTasks()
        startScheduleTimer()
        startFileWatcher()
        // 起動時に設定を読み込んで Slack URL をセット
        let settings = loadSettings()
        slackNotifier.webhookURL = settings.slackWebhookURL
        let count = lock.withLock { tasks.count }
        print("[Scheduler] \(count) 件のタスクで起動しました")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fileWatchTimer?.invalidate()
        fileWatchTimer = nil
    }

    // MARK: - タスク管理

    func reloadTasks() {
        let loaded = taskStore.loadAll()
        lock.withLock {
            tasks = loaded
            recalculateFireDatesLocked()
        }
        print("[Scheduler] 再読み込み: \(loaded.count) 件のタスク")
    }

    func allTaskStatuses() -> [TaskStatus] {
        lock.withLock {
            tasks.map { task in
                TaskStatus(
                    task: task,
                    lastRun: logStore.lastRecord(taskId: task.id),
                    nextRunAt: nextFireDates[task.id],
                    isRunning: executor.isRunning(task.id)
                )
            }
        }
    }

    func runTaskNow(_ taskId: String) {
        let task = lock.withLock { tasks.first { $0.id == taskId } }
        guard let task else {
            print("[Scheduler] タスクが見つかりません: \(taskId)")
            return
        }
        executeTask(task)
    }

    func stopTask(_ taskId: String) {
        executor.stop(taskId)
    }

    func toggleTask(_ taskId: String) {
        let task: TaskDefinition? = lock.withLock {
            guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return nil }
            tasks[idx] = TaskDefinition(
                id: tasks[idx].id,
                name: tasks[idx].name,
                description: tasks[idx].description,
                command: tasks[idx].command,
                workingDirectory: tasks[idx].workingDirectory,
                schedule: tasks[idx].schedule,
                enabled: !tasks[idx].enabled,
                catchUp: tasks[idx].catchUp,
                notifyOnFailure: tasks[idx].notifyOnFailure
            )
            return tasks[idx]
        }
        guard let task else { return }
        do {
            try taskStore.save(task)
        } catch {
            print("[Scheduler] タスク \(taskId) の切り替え保存に失敗: \(error)")
        }
        lock.withLock { recalculateFireDatesLocked() }
        onNotification?(.tasksChanged)
    }

    func saveTask(_ task: TaskDefinition) throws {
        try taskStore.save(task)
        reloadTasks()
        onNotification?(.tasksChanged)
    }

    func deleteTask(_ taskId: String) throws {
        try taskStore.delete(taskId)
        reloadTasks()
        onNotification?(.tasksChanged)
    }

    // MARK: - スリープ復帰

    func handleWake(lastSleepDate: Date) {
        let tasksSnapshot = lock.withLock { tasks }
        print("[Scheduler] スリープ復帰を検知。\(lastSleepDate) 以降の未実行タスクを確認中...")
        for task in tasksSnapshot where task.enabled && task.catchUp {
            if let nextFire = task.schedule.nextFireDate(after: lastSleepDate),
               nextFire < Date() {
                print("[Scheduler] キャッチアップ: \(task.name)")
                executeTask(task)
            }
        }
        lock.withLock { recalculateFireDatesLocked() }
    }

    // MARK: - 設定

    func loadSettings() -> GlobalSettings {
        let url = ConfigPaths.settingsFile
        guard let data = try? Data(contentsOf: url),
              let yaml = String(data: data, encoding: .utf8) else {
            return GlobalSettings()
        }
        return (try? YAMLDecoder().decode(GlobalSettings.self, from: yaml)) ?? GlobalSettings()
    }

    func saveSettings(_ settings: GlobalSettings) throws {
        let yaml = try YAMLEncoder().encode(settings)
        try yaml.write(to: ConfigPaths.settingsFile, atomically: true, encoding: .utf8)
        slackNotifier.webhookURL = settings.slackWebhookURL
    }

    // MARK: - Private

    private func startScheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
    }

    private func startFileWatcher() {
        lastDirModDate = taskStore.directoryModificationDate
        fileWatchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkFileChanges()
        }
    }

    private func checkSchedule() {
        let (tasksSnapshot, fireDates) = lock.withLock { (tasks, nextFireDates) }
        let now = Date()

        for task in tasksSnapshot where task.enabled {
            guard let nextFire = fireDates[task.id], nextFire <= now else { continue }
            executeTask(task)
        }

        lock.withLock { recalculateFireDatesLocked() }
    }

    private func checkFileChanges() {
        let currentModDate = taskStore.directoryModificationDate
        if currentModDate > lastDirModDate {
            lastDirModDate = currentModDate
            reloadTasks()
            onNotification?(.tasksChanged)
        }
    }

    /// ロック保持中に呼ぶこと。
    private func recalculateFireDatesLocked() {
        let now = Date()
        nextFireDates.removeAll()
        for task in tasks where task.enabled {
            nextFireDates[task.id] = task.schedule.nextFireDate(after: now)
        }
    }

    private func executeTask(_ task: TaskDefinition) {
        print("[Scheduler] 実行開始: \(task.name)")
        onNotification?(.taskStarted(task.id))

        // running 状態の仮レコードを保存（UI に実行中表示用）
        let placeholder = ExecutionRecord(taskId: task.id, taskName: task.name, command: task.command, workingDirectory: task.workingDirectory ?? "~")
        logStore.append(placeholder)
        let recordId = placeholder.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.executor.execute(task)
            // 仮レコードを完了結果で更新
            var finalRecord = result
            finalRecord = ExecutionRecord(
                id: recordId,
                taskId: result.taskId,
                taskName: result.taskName,
                command: result.command,
                workingDirectory: result.workingDirectory,
                startedAt: result.startedAt,
                finishedAt: result.finishedAt,
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr,
                status: result.status
            )
            self.logStore.update(finalRecord)
            self.onNotification?(.taskCompleted(task.id, record: finalRecord))

            if finalRecord.status == .failure && task.notifyOnFailure {
                self.slackNotifier.notifyFailure(task: task, record: finalRecord)
            }

            print("[Scheduler] 完了: \(task.name) → \(finalRecord.status.rawValue)")
        }
    }
}
