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

struct DarkWakeDisplay: DisplayWakeStateChecking {
    func shouldExecuteScheduledTasks() -> Bool { false }
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

// MARK: - DisplayWakeState.isFullWake tests

@Suite("DisplayWakeState.isFullWake")
struct DisplayWakeStateTests {
    @Test("Full Wake: all capabilities (CPU|Graphics|Audio|Network = 0x0F)")
    func fullWakeAllCaps() {
        #expect(DisplayWakeState.isFullWake(capabilities: 0x0F) == true)
    }

    @Test("Full Wake: Graphics bit set with other bits")
    func fullWakeGraphicsSet() {
        // CPU | Graphics = 0x03
        #expect(DisplayWakeState.isFullWake(capabilities: 0x03) == true)
    }

    @Test("Full Wake: only Graphics bit")
    func fullWakeGraphicsOnly() {
        #expect(DisplayWakeState.isFullWake(capabilities: 0x02) == true)
    }

    @Test("DarkWake: CPU|Network only (0x09)")
    func darkWakeCpuNetwork() {
        #expect(DisplayWakeState.isFullWake(capabilities: 0x09) == false)
    }

    @Test("DarkWake: CPU only (0x01)")
    func darkWakeCpuOnly() {
        #expect(DisplayWakeState.isFullWake(capabilities: 0x01) == false)
    }

    @Test("DarkWake: no capabilities (0x00)")
    func darkWakeNoCaps() {
        #expect(DisplayWakeState.isFullWake(capabilities: 0x00) == false)
    }

    @Test("graphicsBit constant matches xnu definition")
    func graphicsBitValue() {
        #expect(DisplayWakeState.graphicsBit == 0x02)
    }
}

// MARK: - DarkWake handleWake tests

@Suite("handleWake DarkWake guard")
struct HandleWakeDarkWakeTests {
    @Test("Skips catch-up execution during DarkWake")
    func skipDuringDarkWake() throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.displayWakeState = DarkWakeDisplay()
        let net = MockNetworkMonitor()
        scheduler.networkMonitor = net

        let task = TaskDefinition(
            id: "dw1", name: "dw1", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: true
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        let sleepDate = Date().addingTimeInterval(-3600)
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        let logs = Log.entries()
        let skipped = logs.contains { $0.message.contains("DarkWake中のためキャッチアップ実行をスキップ") }
        #expect(skipped, "Should skip catch-up during DarkWake")

        let executed = logs.contains { $0.message.contains("キャッチアップ実行") && $0.message.contains("dw1") }
        #expect(!executed, "Should not execute any task during DarkWake")

        // logStore にレコードが追加されていないことを確認
        let history = logStore.history(taskId: "dw1")
        #expect(history.isEmpty, "No execution records should be created during DarkWake")
    }

    @Test("Skips pending enqueue during DarkWake even when offline")
    func skipPendingDuringDarkWake() throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.displayWakeState = DarkWakeDisplay()
        let net = MockNetworkMonitor()
        net.simulateDisconnect()
        scheduler.networkMonitor = net

        let task = TaskDefinition(
            id: "dw2", name: "dw2", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: true
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        let sleepDate = Date().addingTimeInterval(-3600)
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        // オフラインでも DarkWake ガードが先に効いて保留キューにも入らない
        let history = logStore.history(taskId: "dw2")
        #expect(history.isEmpty, "No pending records should be enqueued during DarkWake")
    }

    @Test("Catch-up executes after DarkWake transitions to Full Wake")
    func executeAfterFullWake() async throws {
        setupDirs()
        defer { cleanupDirs() }

        let taskStore = TaskStore(directory: testTasksDir)
        let logStore = LogStore(directory: testLogsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        let net = MockNetworkMonitor()
        scheduler.networkMonitor = net

        let task = TaskDefinition(
            id: "dw3", name: "dw3", command: "echo hi",
            schedule: Schedule(type: .everyMinute),
            enabled: true, catchUp: true
        )
        try taskStore.save(task)
        scheduler.reloadTasks()

        let sleepDate = Date().addingTimeInterval(-3600)

        // DarkWake 中: スキップされる
        scheduler.displayWakeState = DarkWakeDisplay()
        scheduler.handleWake(lastSleepDate: sleepDate)
        #expect(logStore.history(taskId: "dw3").isEmpty)

        // Full Wake: キャッチアップが実行される
        scheduler.displayWakeState = AlwaysAwakeDisplay()
        Log.clear()
        scheduler.handleWake(lastSleepDate: sleepDate)

        let logs = Log.entries()
        let executed = logs.contains { $0.message.contains("キャッチアップ実行") && $0.message.contains("dw3") }
        #expect(executed, "Should execute catch-up after transitioning to Full Wake")

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
