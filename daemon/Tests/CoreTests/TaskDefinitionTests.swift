import Testing
import Foundation
@testable import Core

@Suite("TaskDefinition")
struct TaskDefinitionTests {
    @Test("Default timeout is nil")
    func defaultTimeout() {
        let task = TaskDefinition(id: "t", name: "test", command: "echo hi")
        #expect(task.timeout == nil)
    }

    @Test("Timeout can be set via init")
    func timeoutInit() {
        let task = TaskDefinition(id: "t", name: "test", command: "echo hi", timeout: 300)
        #expect(task.timeout == 300)
    }

    @Test("Timeout survives JSON roundtrip")
    func timeoutJsonRoundtrip() throws {
        let task = TaskDefinition(id: "t", name: "test", command: "echo hi", timeout: 60)
        let encoder = JSONEncoder()
        let data = try encoder.encode(task)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TaskDefinition.self, from: data)
        #expect(decoded.timeout == 60)
    }

    @Test("Missing timeout in JSON decodes as nil")
    func missingTimeoutDecodesNil() throws {
        let json = """
        {"id":"t","name":"test","command":"echo hi","schedule":{"type":"every_minute"},"enabled":true,"catch_up":true,"slack_notify":true}
        """
        let decoder = JSONDecoder()
        let task = try decoder.decode(TaskDefinition.self, from: Data(json.utf8))
        #expect(task.timeout == nil)
    }

    @Test("Missing slack_notify in JSON defaults to true (backward compatibility)")
    func missingSlackNotifyDefaultsTrue() throws {
        let json = """
        {"id":"t","name":"test","command":"echo hi","schedule":{"type":"every_minute"},"enabled":true,"catch_up":true}
        """
        let decoder = JSONDecoder()
        let task = try decoder.decode(TaskDefinition.self, from: Data(json.utf8))
        #expect(task.slackNotify == true)
        #expect(task.slackMentions == nil)
    }

    @Test("Missing notify_on_failure in legacy YAML does not break decoding")
    func legacyYamlWithoutSlackNotify() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-compat-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let yaml = """
        id: legacy
        name: Legacy Task
        command: echo legacy
        schedule:
          type: daily
          time: "09:00"
        enabled: true
        catch_up: true
        """
        try yaml.write(
            to: dir.appendingPathComponent("legacy.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.count == 1)
        #expect(tasks[0].slackNotify == true)
    }

    @Test("TaskDefinition with timeout encodes via IPCWireFormat")
    func timeoutWireFormatRoundtrip() throws {
        let task = TaskDefinition(id: "t", name: "test", command: "sleep 999", timeout: 120)
        let request = IPCRequest.saveTask(task)
        let encoded = try IPCWireFormat.encode(request)
        var buffer = encoded
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCRequest.self, from: json)
        #expect(decoded.task?.timeout == 120)
    }
}

// MARK: - TaskDefinition field tests

@Suite("TaskDefinition - fields")
struct TaskDefinitionFieldTests {
    @Test("All fields are set correctly via init")
    func allFields() {
        let task = TaskDefinition(
            id: "my-task",
            name: "My Task",
            description: "A description",
            command: "echo hello",
            workingDirectory: "~/projects",
            schedule: .daily(time: "09:00"),
            enabled: false,
            catchUp: false,
            slackNotify: false,
            slackMentions: ["<!channel>"],
            timeout: 300
        )
        #expect(task.id == "my-task")
        #expect(task.name == "My Task")
        #expect(task.description == "A description")
        #expect(task.command == "echo hello")
        #expect(task.workingDirectory == "~/projects")
        #expect(task.schedule.type == .daily)
        #expect(task.enabled == false)
        #expect(task.catchUp == false)
        #expect(task.slackNotify == false)
        #expect(task.slackMentions == ["<!channel>"])
        #expect(task.timeout == 300)
    }

    @Test("Default values are applied for optional fields")
    func defaults() {
        let task = TaskDefinition(id: "t", name: "test", command: "echo")
        #expect(task.description == nil)
        #expect(task.workingDirectory == nil)
        #expect(task.schedule.type == .daily)
        #expect(task.enabled == true)
        #expect(task.catchUp == true)
        #expect(task.slackNotify == true)
        #expect(task.slackMentions == nil)
        #expect(task.timeout == nil)
    }

    @Test("TaskDefinition is Equatable")
    func equatable() {
        let t1 = TaskDefinition(id: "t", name: "test", command: "echo")
        let t2 = TaskDefinition(id: "t", name: "test", command: "echo")
        #expect(t1 == t2)

        let t3 = TaskDefinition(id: "t", name: "different", command: "echo")
        #expect(t1 != t3)
    }
}

// MARK: - TaskStore YAML parsing tests

@Suite("TaskStore - YAML parsing")
struct TaskStoreYAMLTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-taskstore-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Valid YAML file is parsed correctly")
    func validYAML() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let yaml = """
        id: ignored
        name: Test Task
        command: echo hello
        schedule:
          type: daily
          time: "09:00"
        enabled: true
        catch_up: true
        slack_notify: true
        """
        try yaml.write(
            to: dir.appendingPathComponent("my-task.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "my-task") // ID comes from filename
        #expect(tasks[0].name == "Test Task")
        #expect(tasks[0].command == "echo hello")
        #expect(tasks[0].schedule.type == .daily)
    }

    @Test("Task ID comes from filename, not YAML content")
    func idFromFilename() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let yaml = """
        id: yaml-id
        name: Test
        command: echo test
        schedule:
          type: every_minute
        enabled: true
        catch_up: false
        slack_notify: true
        """
        try yaml.write(
            to: dir.appendingPathComponent("filename-id.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks[0].id == "filename-id")
    }

    @Test("Malformed YAML file is skipped")
    func malformedYAML() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "not: valid: yaml: {{[".write(
            to: dir.appendingPathComponent("bad.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.isEmpty)
    }

    @Test("YAML with missing required fields is skipped")
    func missingRequiredFields() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Missing 'command' field
        let yaml = """
        name: Test
        schedule:
          type: daily
        enabled: true
        catch_up: true
        slack_notify: true
        """
        try yaml.write(
            to: dir.appendingPathComponent("incomplete.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.isEmpty)
    }

    @Test("Mixed valid and invalid files: only valid ones are loaded")
    func mixedFiles() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let validYaml = """
        id: t
        name: Good Task
        command: echo good
        schedule:
          type: every_minute
        enabled: true
        catch_up: true
        slack_notify: true
        """
        try validYaml.write(
            to: dir.appendingPathComponent("good.yaml"),
            atomically: true, encoding: .utf8
        )
        try "{{invalid".write(
            to: dir.appendingPathComponent("bad.yaml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "good")
    }

    @Test("Empty directory returns empty list")
    func emptyDirectory() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.isEmpty)
    }

    @Test("Non-YAML files are ignored")
    func nonYamlFilesIgnored() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try "some text".write(
            to: dir.appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8
        )
        try "{}".write(
            to: dir.appendingPathComponent("data.json"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.isEmpty)
    }

    @Test("Both .yaml and .yml extensions are supported")
    func ymlExtension() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let yaml = """
        id: t
        name: YML Task
        command: echo yml
        schedule:
          type: every_minute
        enabled: true
        catch_up: true
        slack_notify: true
        """
        try yaml.write(
            to: dir.appendingPathComponent("task1.yml"),
            atomically: true, encoding: .utf8
        )

        let store = TaskStore(directory: dir)
        let tasks = store.loadAll()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == "task1")
    }

    @Test("Save and load roundtrip preserves task data")
    func saveAndLoadRoundtrip() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = TaskStore(directory: dir)
        let task = TaskDefinition(
            id: "roundtrip",
            name: "Roundtrip Test",
            description: "Testing save/load",
            command: "echo roundtrip",
            workingDirectory: "~/test",
            schedule: .hourly(minute: 15),
            enabled: true,
            catchUp: false,
            slackNotify: false,
            slackMentions: ["<@U123>"],
            timeout: 60
        )

        try store.save(task)
        let loaded = store.loadAll()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "roundtrip")
        #expect(loaded[0].name == "Roundtrip Test")
        #expect(loaded[0].command == "echo roundtrip")
        #expect(loaded[0].timeout == 60)
    }

    @Test("Delete removes the task file")
    func deleteTask() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = TaskStore(directory: dir)
        let task = TaskDefinition(id: "to-delete", name: "Delete Me", command: "echo bye")
        try store.save(task)

        #expect(store.loadAll().count == 1)

        try store.delete("to-delete")
        #expect(store.loadAll().isEmpty)
    }
}

// MARK: - TaskStoreError tests

@Suite("TaskStoreError - descriptions")
struct TaskStoreErrorTests {
    @Test("directoryReadFailed has descriptive message")
    func directoryReadFailed() {
        let err = TaskStoreError.directoryReadFailed(path: "/some/path", underlying: nil)
        #expect(err.description.contains("/some/path"))
    }

    @Test("fileReadFailed has descriptive message")
    func fileReadFailed() {
        let err = TaskStoreError.fileReadFailed(filename: "test.yaml", underlying: nil)
        #expect(err.description.contains("test.yaml"))
    }

    @Test("yamlParseFailed includes the filename")
    func yamlParseFailed() {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "bad yaml" }
        }
        let err = TaskStoreError.yamlParseFailed(filename: "broken.yaml", underlying: DummyError())
        #expect(err.description.contains("broken.yaml"))
        #expect(err.description.contains("bad yaml"))
    }
}
