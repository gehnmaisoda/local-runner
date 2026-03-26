import Testing
import Foundation
@testable import Core

@Suite("IPCWireFormat")
struct IPCWireFormatTests {
    // MARK: - readMessage

    @Test("Empty buffer returns nil")
    func readFromEmpty() {
        var buffer = Data()
        #expect(IPCWireFormat.readMessage(from: &buffer) == nil)
    }

    @Test("Buffer shorter than 4 bytes returns nil")
    func readFromShort() {
        var buffer = Data([0x00, 0x00, 0x01])
        #expect(IPCWireFormat.readMessage(from: &buffer) == nil)
        // Buffer should be unchanged
        #expect(buffer.count == 3)
    }

    @Test("Header present but insufficient body returns nil")
    func readIncompleteBody() {
        // Header says 10 bytes, but only 5 bytes of body
        var buffer = Data([0x00, 0x00, 0x00, 0x0A, 0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(IPCWireFormat.readMessage(from: &buffer) == nil)
        // Buffer should be unchanged
        #expect(buffer.count == 9)
    }

    @Test("Exact complete message is extracted")
    func readExactMessage() {
        let body = Data([0x7B, 0x7D]) // "{}"
        var buffer = Data([0x00, 0x00, 0x00, 0x02]) + body
        let result = IPCWireFormat.readMessage(from: &buffer)
        #expect(result == body)
        #expect(buffer.isEmpty)
    }

    @Test("Multiple messages: first is extracted, remainder stays")
    func readMultipleMessages() {
        let body1 = Data([0x41, 0x42]) // "AB"
        let body2 = Data([0x43, 0x44, 0x45]) // "CDE"
        var buffer = Data([0x00, 0x00, 0x00, 0x02]) + body1
                   + Data([0x00, 0x00, 0x00, 0x03]) + body2

        let result1 = IPCWireFormat.readMessage(from: &buffer)
        #expect(result1 == body1)
        #expect(buffer.count == 7) // 4 + 3

        let result2 = IPCWireFormat.readMessage(from: &buffer)
        #expect(result2 == body2)
        #expect(buffer.isEmpty)
    }

    @Test("Zero-length message returns empty data")
    func readZeroLengthMessage() {
        var buffer = Data([0x00, 0x00, 0x00, 0x00])
        let result = IPCWireFormat.readMessage(from: &buffer)
        #expect(result == Data())
        #expect(buffer.isEmpty)
    }

    @Test("Large length prefix (64KB) works")
    func readLargeMessage() {
        let size = 65536
        let body = Data(repeating: 0x42, count: size)
        var lengthBytes = Data(count: 4)
        lengthBytes[0] = UInt8((size >> 24) & 0xFF)
        lengthBytes[1] = UInt8((size >> 16) & 0xFF)
        lengthBytes[2] = UInt8((size >> 8) & 0xFF)
        lengthBytes[3] = UInt8(size & 0xFF)
        var buffer = lengthBytes + body

        let result = IPCWireFormat.readMessage(from: &buffer)
        #expect(result?.count == size)
        #expect(buffer.isEmpty)
    }

    // MARK: - encode/decode roundtrip

    @Test("IPCRequest encode and decode roundtrip")
    func requestRoundtrip() throws {
        let request = IPCRequest.runTask("my-task")
        let encoded = try IPCWireFormat.encode(request)

        // First 4 bytes are the length prefix
        #expect(encoded.count > 4)
        var buffer = encoded
        let json = IPCWireFormat.readMessage(from: &buffer)
        #expect(json != nil)
        #expect(buffer.isEmpty)

        let decoded = try IPCWireFormat.decode(IPCRequest.self, from: json!)
        #expect(decoded.action == "run_task")
        #expect(decoded.taskId == "my-task")
    }

    @Test("IPCResponse encode and decode roundtrip")
    func responseRoundtrip() throws {
        let response = IPCResponse.error("something failed")
        let encoded = try IPCWireFormat.encode(response)
        var buffer = encoded
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(IPCResponse.self, from: json)
        #expect(decoded.success == false)
        #expect(decoded.error == "something failed")
    }

    @Test("Date survives encode/decode roundtrip")
    func dateRoundtrip() throws {
        let now = Date()
        let record = ExecutionRecord(taskId: "t", taskName: "test", startedAt: now)
        let encoded = try IPCWireFormat.encode(record)
        var buffer = encoded
        let json = IPCWireFormat.readMessage(from: &buffer)!
        let decoded = try IPCWireFormat.decode(ExecutionRecord.self, from: json)
        // Allow 1ms tolerance for fractional second rounding
        #expect(abs(decoded.startedAt.timeIntervalSince(now)) < 0.001)
    }

    @Test("Multiple messages in sequence maintain integrity")
    func sequentialMessages() throws {
        let req1 = IPCRequest.listTasks
        let req2 = IPCRequest.runTask("task-a")
        let req3 = IPCRequest.getHistory(taskId: "task-b", limit: 10)

        var buffer = try IPCWireFormat.encode(req1)
        buffer.append(try IPCWireFormat.encode(req2))
        buffer.append(try IPCWireFormat.encode(req3))

        let json1 = IPCWireFormat.readMessage(from: &buffer)!
        let json2 = IPCWireFormat.readMessage(from: &buffer)!
        let json3 = IPCWireFormat.readMessage(from: &buffer)!
        #expect(buffer.isEmpty)

        let d1 = try IPCWireFormat.decode(IPCRequest.self, from: json1)
        let d2 = try IPCWireFormat.decode(IPCRequest.self, from: json2)
        let d3 = try IPCWireFormat.decode(IPCRequest.self, from: json3)

        #expect(d1.action == "list_tasks")
        #expect(d2.action == "run_task")
        #expect(d2.taskId == "task-a")
        #expect(d3.action == "get_history")
        #expect(d3.limit == 10)
    }
}
