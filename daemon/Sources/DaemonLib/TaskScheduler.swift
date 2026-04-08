import Foundation
import Yams
import Core

/// タスクのスケジューリングと実行を管理する。
public final class TaskScheduler: @unchecked Sendable {
    private let taskStore: TaskStore
    private let logStore: LogStore
    private let executor = TaskExecutor()
    private let slackNotifier = SlackNotifier()
    public var displayWakeState: DisplayWakeStateChecking = DisplayWakeState()

    private var tasks: [TaskDefinition] = []
    private var nextFireDates: [String: Date] = [:]

    private var timer: Timer?
    private var fileWatchTimer: Timer?
    private var lastDirModDate: Date = .distantPast
    private let lock = NSLock()
    private var isDarkWakePaused = false
    private var isShuttingDown = false
    private var cachedSettings = GlobalSettings()

    /// ネットワーク未接続時の保留キュー（タスクID → タスク定義 + プレースホルダーのレコードID）。
    /// 各タスクにつき最大1件保留。復帰時に同じレコードを更新する。
    private var pendingTasks: [String: (task: TaskDefinition, recordId: UUID)] = [:]

    /// ネットワーク監視
    public var networkMonitor: NetworkChecking = NetworkMonitor()

    /// IPC通知用コールバック
    public var onNotification: ((IPCNotification) -> Void)?

    public init(taskStore: TaskStore, logStore: LogStore) {
        self.taskStore = taskStore
        self.logStore = logStore
    }

    // MARK: - 起動・停止

    public func start() {
        logStore.cleanupOrphanedRecords()
        reloadTasks()
        startScheduleTimer()
        startFileWatcher()
        // 起動時に設定を読み込んで反映
        let settings = loadSettings()
        lock.withLock { cachedSettings = settings }
        slackNotifier.botToken = settings.slackBotToken
        slackNotifier.channel = settings.slackChannel

        // ネットワーク監視を起動
        networkMonitor.onRestore = { [weak self] in
            self?.executePendingTasks()
        }
        networkMonitor.start()

        let count = lock.withLock { tasks.count }
        Log.info("Scheduler", "\(count) 件のタスクで起動しました")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        fileWatchTimer?.invalidate()
        fileWatchTimer = nil
        networkMonitor.stop()
    }

    /// Graceful shutdown: タイマー停止 → 実行中タスク停止。
    public func shutdown() {
        lock.withLock { isShuttingDown = true }
        stop()
        executor.stopAll(timeout: 5)
        Log.info("Scheduler", "シャットダウン完了")
    }

    // MARK: - タスク管理

    public func reloadTasks() {
        let loaded = taskStore.loadAll()
        lock.withLock {
            tasks = loaded
            recalculateFireDatesLocked()
        }
        Log.info("Scheduler", "再読み込み: \(loaded.count) 件のタスク")
    }

    public func allTaskStatuses() -> [TaskStatus] {
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

    public func runTaskNow(_ taskId: String) {
        let task = lock.withLock { tasks.first { $0.id == taskId } }
        guard let task else {
            Log.info("Scheduler", "タスクが見つかりません: \(taskId)")
            return
        }
        executeTask(task)
    }

    public func stopTask(_ taskId: String) {
        executor.stop(taskId)
    }

    public func toggleTask(_ taskId: String) {
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
                slackNotify: tasks[idx].slackNotify,
                slackMentions: tasks[idx].slackMentions,
                timeout: tasks[idx].timeout
            )
            recalculateFireDatesLocked()
            return tasks[idx]
        }
        guard let task else { return }
        do {
            try taskStore.save(task)
        } catch {
            Log.info("Scheduler", "タスク \(taskId) の切り替え保存に失敗: \(error)")
        }
        onNotification?(.tasksChanged)
    }

    public func saveTask(_ task: TaskDefinition) throws {
        try taskStore.save(task)
        reloadTasks()
        onNotification?(.tasksChanged)
    }

    public func deleteTask(_ taskId: String) throws {
        try taskStore.delete(taskId)
        logStore.deleteHistory(taskId: taskId)
        reloadTasks()
        onNotification?(.tasksChanged)
    }

    // MARK: - スリープ復帰

    public func handleWake(lastSleepDate: Date) {
        guard displayWakeState.shouldExecuteScheduledTasks() else {
            Log.info("Scheduler", "DarkWake中のためキャッチアップ実行をスキップ")
            return
        }

        let tasksSnapshot = lock.withLock { tasks }
        Log.info("Scheduler", "スリープ復帰を検知。\(Log.formatDate(lastSleepDate)) 以降の未実行タスクを確認中...")

        let now = Date()
        let catchUpTasks = tasksSnapshot.filter { task in
            guard task.enabled, task.catchUp else { return false }
            guard let nextFire = task.schedule.nextFireDate(after: lastSleepDate) else { return false }
            guard nextFire < now else { return false }

            // スリープ期間中に既に実行済みならスキップ
            if let lastRun = logStore.lastRecord(taskId: task.id),
               lastRun.startedAt >= lastSleepDate {
                Log.info("Scheduler", "キャッチアップ棄却: \(task.name) はスリープ期間中に実行済み (\(Log.formatDate(lastRun.startedAt)))")
                return false
            }
            return true
        }

        if networkMonitor.isConnected {
            for task in catchUpTasks {
                Log.info("Scheduler", "キャッチアップ実行: \(task.name)")
                executeTask(task)
            }
        } else {
            // オフラインなら保留キューに入れて、ネットワーク復帰時にまとめて実行
            var newRecords: [ExecutionRecord] = []
            lock.lock()
            for task in catchUpTasks {
                if let record = tryEnqueuePending(task) { newRecords.append(record) }
            }
            lock.unlock()
            commitPendingRecords(newRecords)
        }
        lock.withLock { recalculateFireDatesLocked() }
    }

    // MARK: - ネットワーク復帰

    /// ネットワーク復帰時に保留キューのタスクを実行する。
    /// 保留時に作成済みのプレースホルダーレコードを再利用する。
    private func executePendingTasks() {
        let pending: [(task: TaskDefinition, recordId: UUID)]
        lock.lock()
        pending = Array(pendingTasks.values)
        pendingTasks.removeAll()
        lock.unlock()

        if !pending.isEmpty {
            Log.info("Scheduler", "ネットワーク復帰: 保留中の \(pending.count) 件のタスクを実行します")
            for entry in pending {
                executeTaskWithRecord(entry.task, recordId: entry.recordId)
            }
        }
    }

    /// タスクが保留可能かチェックし、可能ならキューに登録する。
    /// lock を保持した状態で呼ぶこと。副作用のあるレコード追加・通知は返り値で呼び出し元が行う。
    private func tryEnqueuePending(_ task: TaskDefinition) -> ExecutionRecord? {
        guard pendingTasks[task.id] == nil else {
            Log.info("Scheduler", "オフライン: \(task.name) は既に保留中のため棄却")
            return nil
        }

        let placeholder = ExecutionRecord(
            taskId: task.id, taskName: task.name,
            command: task.command, workingDirectory: task.workingDirectory ?? "~",
            status: .pending
        )
        pendingTasks[task.id] = (task: task, recordId: placeholder.id)
        Log.info("Scheduler", "オフライン: \(task.name) を保留キューに追加")
        return placeholder
    }

    /// 保留キューへの追加結果を元に、lock の外で副作用（ログ書き込み・IPC通知）を実行する。
    private func commitPendingRecords(_ records: [ExecutionRecord]) {
        for record in records {
            logStore.append(record)
            onNotification?(.taskStarted(record.taskId))
        }
    }

    // MARK: - 設定

    public func loadSettings() -> GlobalSettings {
        let url = ConfigPaths.settingsFile
        guard let data = try? Data(contentsOf: url),
              let yaml = String(data: data, encoding: .utf8) else {
            return GlobalSettings()
        }
        return (try? YAMLDecoder().decode(GlobalSettings.self, from: yaml)) ?? GlobalSettings()
    }

    public func saveSettings(_ settings: GlobalSettings) throws {
        let yaml = try YAMLEncoder().encode(settings)
        try yaml.write(to: ConfigPaths.settingsFile, atomically: true, encoding: .utf8)
        lock.withLock { cachedSettings = settings }
        slackNotifier.botToken = settings.slackBotToken
        slackNotifier.channel = settings.slackChannel
    }

    // MARK: - Private

    private func startScheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
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
        guard displayWakeState.shouldExecuteScheduledTasks() else {
            if !isDarkWakePaused {
                isDarkWakePaused = true
                Log.info("Scheduler", "DarkWake検知: スケジュール実行を一時停止します")
            }
            // fire date は進めない → ディスプレイ復帰後にまとめて実行される
            return
        }
        if isDarkWakePaused {
            isDarkWakePaused = false
            Log.info("Scheduler", "ディスプレイ復帰: スケジュール実行を再開します")
        }

        let (tasksSnapshot, fireDates) = lock.withLock { (tasks, nextFireDates) }
        let now = Date()
        let dueTasks = ScheduleLogic.dueTasks(from: tasksSnapshot, nextFireDates: fireDates, at: now)

        if networkMonitor.isConnected {
            for task in dueTasks {
                executeTask(task)
            }
        } else {
            // オフライン時: 各タスクにつき1件まで保留（プレースホルダー付き）
            var newRecords: [ExecutionRecord] = []
            lock.lock()
            for task in dueTasks {
                if let record = tryEnqueuePending(task) { newRecords.append(record) }
            }
            lock.unlock()
            commitPendingRecords(newRecords)
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
        nextFireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: Date())
    }

    private func executeTask(_ task: TaskDefinition) {
        guard !lock.withLock({ isShuttingDown }) else { return }
        Log.info("Scheduler", "実行開始: \(task.name)")
        onNotification?(.taskStarted(task.id))

        // running 状態の仮レコードを保存（UI に実行中表示用）
        let placeholder = ExecutionRecord(taskId: task.id, taskName: task.name, command: task.command, workingDirectory: task.workingDirectory ?? "~")
        logStore.append(placeholder)

        runTask(task, recordId: placeholder.id)
    }

    /// 保留キューから復帰したタスクを実行する。プレースホルダーは保留時に作成済み。
    private func executeTaskWithRecord(_ task: TaskDefinition, recordId: UUID) {
        guard !lock.withLock({ isShuttingDown }) else { return }
        Log.info("Scheduler", "実行開始（保留復帰）: \(task.name)")
        onNotification?(.taskStarted(task.id))

        runTask(task, recordId: recordId)
    }

    /// タスクを非同期実行し、指定レコードIDで結果を更新する。
    private func runTask(_ task: TaskDefinition, recordId: UUID) {
        let defaultTimeout = lock.withLock { cachedSettings.effectiveDefaultTimeout }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.executor.execute(task, defaultTimeout: defaultTimeout)
            let finalRecord = ExecutionRecord(
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

            // 手動停止の場合は通知しない
            if task.slackNotify && finalRecord.status != .stopped {
                self.slackNotifier.notifyCompletion(task: task, record: finalRecord)
            }

            let duration = finalRecord.durationText
            Log.info("Scheduler", "完了: \(task.name) → \(finalRecord.status.rawValue) (\(duration))")
        }
    }
}
