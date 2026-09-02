import Testing
import Foundation
@testable import Core
@testable import DaemonLib

private final class EventNetworkMonitor: NetworkChecking, @unchecked Sendable {
    var isConnected = true
    var onRestore: (() -> Void)?
    func start() {}
    func stop() {}
}

@Suite("TaskScheduler event dispatch")
struct EventSchedulerTests {
    @Test("Matching topic runs once with event environment and records metadata")
    func matchingTopic() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-runner-event-scheduler-\(UUID().uuidString)")
        let tasks = root.appendingPathComponent("tasks")
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let taskStore = TaskStore(directory: tasks)
        try taskStore.save(TaskDefinition(
            id: "event-task",
            name: "Event task",
            command: "test \"$LR_EVENT_ID\" = \"demo:1\" && test \"$LR_EVENT_TOPIC\" = \"demo.completed\" && test -f \"$LR_EVENT_FILE\"",
            workingDirectory: root.path,
            schedule: .event("demo.completed"),
            catchUp: false,
            slackNotify: false
        ))
        let logStore = LogStore(directory: logs)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        scheduler.networkMonitor = EventNetworkMonitor()
        scheduler.start()
        defer { scheduler.shutdown() }

        let payload = root.appendingPathComponent("event.json")
        try Data("{}".utf8).write(to: payload)
        let completed = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var succeeded = false
        scheduler.runEvent(TaskEvent(
            id: "demo:1", topic: "demo.completed", payloadFile: payload.path, attempt: 1
        )) { result in
            succeeded = result
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 5) == .success)
        #expect(succeeded)
        let record = try #require(logStore.lastRecord(taskId: "event-task"))
        #expect(record.status == .success)
        #expect(record.trigger == .event)
        #expect(record.eventId == "demo:1")
        #expect(record.eventTopic == "demo.completed")
    }

    @Test("Missing topic handler returns failure without execution")
    func missingHandler() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-runner-event-missing-\(UUID().uuidString)")
        let tasks = root.appendingPathComponent("tasks")
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let scheduler = TaskScheduler(taskStore: TaskStore(directory: tasks), logStore: LogStore(directory: logs))
        scheduler.networkMonitor = EventNetworkMonitor()
        scheduler.start()
        defer { scheduler.shutdown() }
        let completed = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var succeeded = true
        scheduler.runEvent(TaskEvent(
            id: "demo:1", topic: "missing.topic", payloadFile: "/tmp/missing", attempt: 1
        )) { result in
            succeeded = result
            completed.signal()
        }

        #expect(completed.wait(timeout: .now() + 1) == .success)
        #expect(!succeeded)
    }
}
