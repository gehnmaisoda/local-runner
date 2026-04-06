import Testing
import Foundation
@testable import Core
@testable import DaemonLib

@Suite("Log ring buffer", .serialized)
struct LogBufferTests {
    init() {
        Log.clear()
    }

    @Test("info() stores entries in buffer")
    func storesEntries() {
        Log.info("Test", "message 1")
        Log.info("Test", "message 2")

        let entries = Log.entries()
        #expect(entries.count == 2)
        #expect(entries[0].tag == "Test")
        #expect(entries[0].message == "message 1")
        #expect(entries[1].message == "message 2")
    }

    @Test("entries(limit:) returns only the last N entries")
    func entriesLimit() {
        for i in 0..<10 {
            Log.info("T", "msg \(i)")
        }

        let entries = Log.entries(limit: 3)
        #expect(entries.count == 3)
        #expect(entries[0].message == "msg 7")
        #expect(entries[2].message == "msg 9")
    }

    @Test("clear() empties the buffer")
    func clearBuffer() {
        Log.info("T", "hello")
        #expect(Log.entries().count == 1)

        Log.clear()
        #expect(Log.entries().count == 0)
    }

    @Test("LogEntry fields are populated correctly")
    func entryFields() {
        let before = Date()
        Log.info("Wake", "test message")
        let after = Date()

        let entry = Log.entries().last!
        #expect(entry.tag == "Wake")
        #expect(entry.message == "test message")
        #expect(entry.timestamp >= before)
        #expect(entry.timestamp <= after)
    }
}
