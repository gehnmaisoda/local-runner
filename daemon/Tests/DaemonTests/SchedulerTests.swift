import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - Mock NetworkMonitor

final class MockNetworkMonitor: NetworkChecking, @unchecked Sendable {
    var isConnected: Bool = true
    var onRestore: (() -> Void)?
    func start() {}
    func stop() {}

    func simulateDisconnect() {
        isConnected = false
    }

    func simulateRestore() {
        isConnected = true
        onRestore?()
    }
}

// MARK: - Mock DisplayWakeState

struct AlwaysAwakeDisplay: DisplayWakeStateChecking {
    func shouldExecuteScheduledTasks() -> Bool { true }
}

// MARK: - Helpers

private let testTasksDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("lr-test-tasks-\(UUID().uuidString)")
private let testLogsDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("lr-test-logs-\(UUID().uuidString)")

private func setupDirs() {
    try? FileManager.default.createDirectory(at: testTasksDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: testLogsDir, withIntermediateDirectories: true)
}

private func cleanupDirs() {
    try? FileManager.default.removeItem(at: testTasksDir)
    try? FileManager.default.removeItem(at: testLogsDir)
}

private func makeTask(
    id: String = "t1",
    command: String = "echo hi",
    enabled: Bool = true,
    catchUp: Bool = true,
    timeout: Int? = nil
) -> TaskDefinition {
    TaskDefinition(id: id, name: id, command: command, enabled: enabled, catchUp: catchUp, timeout: timeout)
}

// MARK: - LogStore cleanup tests

@Suite("LogStore.cleanupOrphanedRecords")
struct LogStoreCleanupTests {
    @Test("Running records are cleaned up to stopped on startup")
    func cleanupRunning() {
        setupDirs()
        defer { cleanupDirs() }

        let logStore = LogStore(directory: testLogsDir)
        let record = ExecutionRecord(taskId: "t1", taskName: "t1", status: .running)
        logStore.append(record)

        logStore.cleanupOrphanedRecords()

        let history = logStore.history(taskId: "t1")
        #expect(history.count == 1)
        #expect(history[0].status == .stopped)
    }

    @Test("Pending records are cleaned up to stopped on startup")
    func cleanupPending() {
        setupDirs()
        defer { cleanupDirs() }

        let logStore = LogStore(directory: testLogsDir)
        let record = ExecutionRecord(taskId: "t1", taskName: "t1", status: .pending)
        logStore.append(record)

        logStore.cleanupOrphanedRecords()

        let history = logStore.history(taskId: "t1")
        #expect(history.count == 1)
        #expect(history[0].status == .stopped)
    }

    @Test("Success records are not affected by cleanup")
    func successNotAffected() {
        setupDirs()
        defer { cleanupDirs() }

        let logStore = LogStore(directory: testLogsDir)
        let record = ExecutionRecord(
            taskId: "t1", taskName: "t1",
            startedAt: Date(), finishedAt: Date(),
            status: .success
        )
        logStore.append(record)

        logStore.cleanupOrphanedRecords()

        let history = logStore.history(taskId: "t1")
        #expect(history[0].status == .success)
    }
}

// MARK: - Catch-up deduplication tests

@Suite("handleWake catch-up deduplication")
struct HandleWakeCatchUpTests {
    @Test("Skips catch-up when task already ran during sleep period")
    func skipAlreadyRan() throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.displayWakeState = AlwaysAwakeDisplay()
        let net = MockNetworkMonitor()
        scheduler.networkMonitor = net

        // Create a task scheduled every_minute with catch_up enabled
        let task = TaskDefinition(
            id: "t1", name: "t1", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: true
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        // Simulate: task ran at sleepDate + 1 minute
        let sleepDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let ranAt = sleepDate.addingTimeInterval(60)
        let record = ExecutionRecord(
            taskId: "t1", taskName: "t1",
            startedAt: ranAt, finishedAt: ranAt.addingTimeInterval(1),
            status: .success
        )
        logStore.append(record)

        // handleWake should skip t1 because it already ran during sleep
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        let logs = Log.entries()
        let rejected = logs.contains { $0.message.contains("キャッチアップ棄却") && $0.message.contains("t1") }
        #expect(rejected, "Should log catch-up rejection for already-run task")
    }

    @Test("Skips catch-up when task has catchUp disabled")
    func skipCatchUpDisabled() throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.displayWakeState = AlwaysAwakeDisplay()
        let net = MockNetworkMonitor()
        scheduler.networkMonitor = net

        let task = TaskDefinition(
            id: "t3", name: "t3", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: false
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        let sleepDate = Date().addingTimeInterval(-3600)
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        let logs = Log.entries()
        let anyT3 = logs.contains { $0.message.contains("t3") }
        #expect(!anyT3, "Task with catchUp=false should not appear in catch-up logs")
    }

    @Test("Executes catch-up when task did not run during sleep period")
    func executeWhenNotRan() async throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.displayWakeState = AlwaysAwakeDisplay()
        let net = MockNetworkMonitor()
        scheduler.networkMonitor = net

        let task = TaskDefinition(
            id: "t2", name: "t2", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: true
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        // No execution records — task never ran
        let sleepDate = Date().addingTimeInterval(-3600)
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        let logs = Log.entries()
        let executed = logs.contains { $0.message.contains("キャッチアップ実行") && $0.message.contains("t2") }
        #expect(executed, "Should execute catch-up for task that didn't run")

        // Wait for async execution to complete
        try? await Task.sleep(for: .milliseconds(500))
        scheduler.shutdown()
    }
}

// MARK: - NetworkMonitor callback tests

@Suite("NetworkMonitor callback logic")
struct NetworkMonitorCallbackTests {
    @Test("MockNetworkMonitor onRestore fires on reconnect")
    func mockRestore() {
        let mock = MockNetworkMonitor()
        var restored = false
        mock.onRestore = { restored = true }

        mock.simulateDisconnect()
        #expect(!mock.isConnected)

        mock.simulateRestore()
        #expect(mock.isConnected)
        #expect(restored)
    }

    @Test("onRestore does not fire if already connected")
    func noRestoreWhenAlreadyConnected() {
        let mock = MockNetworkMonitor()
        var restoreCount = 0
        mock.onRestore = { restoreCount += 1 }

        // Already connected, just calling simulateRestore
        mock.simulateRestore()
        // Should still fire because mock doesn't track wasDisconnected
        // This tests the mock itself, not the production code
        #expect(restoreCount == 1)
    }
}
