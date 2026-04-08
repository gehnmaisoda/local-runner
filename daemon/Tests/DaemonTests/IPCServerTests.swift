import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - Wire format encoding/decoding tests

@Suite("IPCServer - wire format")
struct IPCServerWireFormatTests {
    @Test("IPCRequest list_tasks encodes correctly")
    func encodeListTasks() throws {
        let request = IPCRequest.listTasks
        let data = try IPCWireFormat.encode(request)
        // Should have 4-byte length prefix + JSON body
        #expect(data.count > 4)

        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)
        #expect(json != nil)
        let decoded = try IPCWireFormat.decode(IPCRequest.self, from: json!)
        #expect(decoded.action == "list_tasks")
    }

    @Test("IPCRequest run_task includes taskId")
    func encodeRunTask() throws {
        let request = IPCRequest.runTask("my-task-123")
        let data = try IPCWireFormat.encode(request)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCRequest.self, from: json)
        #expect(decoded.action == "run_task")
        #expect(decoded.taskId == "my-task-123")
    }

    @Test("IPCRequest get_history includes limit")
    func encodeGetHistory() throws {
        let request = IPCRequest.getHistory(taskId: "t1", limit: 25)
        let data = try IPCWireFormat.encode(request)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCRequest.self, from: json)
        #expect(decoded.action == "get_history")
        #expect(decoded.taskId == "t1")
        #expect(decoded.limit == 25)
    }

    @Test("IPCResponse ok is encoded correctly")
    func encodeOkResponse() throws {
        let response = IPCResponse.ok
        let data = try IPCWireFormat.encode(response)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.success == true)
        #expect(decoded.error == nil)
    }

    @Test("IPCResponse error carries the message")
    func encodeErrorResponse() throws {
        let response = IPCResponse.error("task not found")
        let data = try IPCWireFormat.encode(response)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.success == false)
        #expect(decoded.error == "task not found")
    }

    @Test("IPCResponse with tasks includes task data")
    func encodeTasksResponse() throws {
        let task = TaskDefinition(id: "t1", name: "Test", command: "echo hi")
        let status = TaskStatus(task: task, isRunning: false)
        let response = IPCResponse(tasks: [status])
        let data = try IPCWireFormat.encode(response)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.tasks?.count == 1)
        #expect(decoded.tasks?[0].task.id == "t1")
    }

    @Test("IPCResponse with version encodes and decodes correctly")
    func encodeVersionResponse() throws {
        let response = IPCResponse(version: "0.1.0")
        let data = try IPCWireFormat.encode(response)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.success == true)
        #expect(decoded.version == "0.1.0")
        #expect(decoded.tasks == nil)
    }

    @Test("IPCResponse with history includes execution records")
    func encodeHistoryResponse() throws {
        let record = ExecutionRecord(taskId: "t1", taskName: "Test", status: .success)
        let response = IPCResponse(history: [record])
        let data = try IPCWireFormat.encode(response)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.history?.count == 1)
        #expect(decoded.history?[0].taskId == "t1")
    }
}

// MARK: - IPCNotification tests

@Suite("IPCServer - notifications")
struct IPCNotificationTests {
    @Test("taskStarted notification encodes correctly")
    func taskStarted() throws {
        let notification = IPCNotification.taskStarted("my-task")
        let data = try IPCWireFormat.encode(notification)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCNotification.self, from: json)
        #expect(decoded.event == "task_started")
        #expect(decoded.taskId == "my-task")
    }

    @Test("taskCompleted notification includes record")
    func taskCompleted() throws {
        let record = ExecutionRecord(
            taskId: "t1", taskName: "Test",
            startedAt: Date(), finishedAt: Date(),
            exitCode: 0, status: .success
        )
        let notification = IPCNotification.taskCompleted("t1", record: record)
        let data = try IPCWireFormat.encode(notification)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCNotification.self, from: json)
        #expect(decoded.event == "task_completed")
        #expect(decoded.record?.status == .success)
    }

    @Test("tasksChanged notification has correct event")
    func tasksChanged() throws {
        let notification = IPCNotification.tasksChanged
        let data = try IPCWireFormat.encode(notification)
        var buffer = data
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCNotification.self, from: json)
        #expect(decoded.event == "tasks_changed")
        #expect(decoded.taskId == nil)
    }
}

// MARK: - IPCRequest factory methods

@Suite("IPCRequest - factory methods")
struct IPCRequestFactoryTests {
    @Test("listTasks creates correct action")
    func listTasks() {
        let req = IPCRequest.listTasks
        #expect(req.action == "list_tasks")
        #expect(req.taskId == nil)
    }

    @Test("runTask includes taskId")
    func runTask() {
        let req = IPCRequest.runTask("abc")
        #expect(req.action == "run_task")
        #expect(req.taskId == "abc")
    }

    @Test("stopTask includes taskId")
    func stopTask() {
        let req = IPCRequest.stopTask("xyz")
        #expect(req.action == "stop_task")
        #expect(req.taskId == "xyz")
    }

    @Test("getHistory with defaults")
    func getHistoryDefaults() {
        let req = IPCRequest.getHistory()
        #expect(req.action == "get_history")
        #expect(req.taskId == nil)
        #expect(req.limit == 50)
    }

    @Test("getHistory with custom params")
    func getHistoryCustom() {
        let req = IPCRequest.getHistory(taskId: "t", limit: 10)
        #expect(req.action == "get_history")
        #expect(req.taskId == "t")
        #expect(req.limit == 10)
    }

    @Test("reload creates correct action")
    func reload() {
        let req = IPCRequest.reload
        #expect(req.action == "reload")
    }

    @Test("getSettings creates correct action")
    func getSettings() {
        let req = IPCRequest.getSettings
        #expect(req.action == "get_settings")
    }

    @Test("updateSettings includes settings")
    func updateSettings() {
        let settings = GlobalSettings(slackBotToken: "xoxb-test", slackChannel: "C123", defaultTimeout: 120)
        let req = IPCRequest.updateSettings(settings)
        #expect(req.action == "update_settings")
        #expect(req.settings?.slackBotToken == "xoxb-test")
        #expect(req.settings?.slackChannel == "C123")
        #expect(req.settings?.defaultTimeout == 120)
    }

    @Test("saveTask includes task")
    func saveTask() {
        let task = TaskDefinition(id: "t1", name: "Test", command: "echo")
        let req = IPCRequest.saveTask(task)
        #expect(req.action == "save_task")
        #expect(req.task?.id == "t1")
    }

    @Test("deleteTask includes taskId")
    func deleteTask() {
        let req = IPCRequest.deleteTask("del-me")
        #expect(req.action == "delete_task")
        #expect(req.taskId == "del-me")
    }

    @Test("toggleTask includes taskId")
    func toggleTask() {
        let req = IPCRequest.toggleTask("toggle-me")
        #expect(req.action == "toggle_task")
        #expect(req.taskId == "toggle-me")
    }

    @Test("getVersion creates correct action")
    func getVersion() {
        let req = IPCRequest.getVersion
        #expect(req.action == "get_version")
        #expect(req.taskId == nil)
    }

    @Test("subscribe creates correct action")
    func subscribe() {
        let req = IPCRequest.subscribe
        #expect(req.action == "subscribe")
    }
}

// MARK: - IPCServer shutdown behavior

@Suite("IPCServer - shutdown flag")
struct IPCServerShutdownTests {
    @Test("isShutdown is false initially")
    func initialState() {
        let logsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-ipc-test-\(UUID().uuidString)")
        let tasksDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-ipc-tasks-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: logsDir)
            try? FileManager.default.removeItem(at: tasksDir)
        }

        let taskStore = TaskStore(directory: tasksDir)
        let logStore = LogStore(directory: logsDir)
        let scheduler = TaskScheduler(taskStore: taskStore, logStore: logStore)
        let server = IPCServer(scheduler: scheduler, logStore: logStore, socketPath: "/tmp/lr-test-\(UUID().uuidString).sock")

        #expect(!server.isShutdown)
    }
}
