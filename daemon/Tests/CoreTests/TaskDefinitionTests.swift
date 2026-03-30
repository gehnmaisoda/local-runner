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
        {"id":"t","name":"test","command":"echo hi","schedule":{"type":"every_minute"},"enabled":true,"catch_up":true,"notify_on_failure":false}
        """
        let decoder = JSONDecoder()
        let task = try decoder.decode(TaskDefinition.self, from: Data(json.utf8))
        #expect(task.timeout == nil)
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
