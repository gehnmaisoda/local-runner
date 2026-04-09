import Testing
import Foundation
@testable import Core

@Suite("ExecutionRecord.durationText")
struct DurationTextTests {
    private func record(duration seconds: TimeInterval) -> ExecutionRecord {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let finish = start.addingTimeInterval(seconds)
        return ExecutionRecord(
            taskId: "t", taskName: "test",
            startedAt: start, finishedAt: finish,
            status: .success
        )
    }

    @Test("Running (no finishedAt) shows dash")
    func running() {
        let r = ExecutionRecord(taskId: "t", taskName: "test")
        #expect(r.durationText == "—")
    }

    @Test("Sub-second shows milliseconds")
    func milliseconds() {
        #expect(record(duration: 0.5).durationText == "500ms")
        #expect(record(duration: 0.001).durationText == "1ms")
        #expect(record(duration: 0.999).durationText == "999ms")
    }

    @Test("Zero duration shows 0ms")
    func zero() {
        #expect(record(duration: 0.0).durationText == "0ms")
    }

    @Test("Boundary at 1 second switches to seconds format")
    func oneSecond() {
        #expect(record(duration: 1.0).durationText == "1.0s")
    }

    @Test("Seconds with decimal")
    func seconds() {
        #expect(record(duration: 5.5).durationText == "5.5s")
        #expect(record(duration: 59.9).durationText == "59.9s")
    }

    @Test("Boundary at 60 seconds switches to minutes format")
    func oneMinute() {
        #expect(record(duration: 60.0).durationText == "1m0s")
    }

    @Test("Minutes and seconds")
    func minutesAndSeconds() {
        #expect(record(duration: 90.0).durationText == "1m30s")
        #expect(record(duration: 3599.0).durationText == "59m59s")
    }

    @Test("Boundary at 3600 seconds switches to hours format")
    func oneHour() {
        #expect(record(duration: 3600.0).durationText == "1h0m")
    }

    @Test("Hours and minutes")
    func hoursAndMinutes() {
        #expect(record(duration: 3660.0).durationText == "1h1m")
        #expect(record(duration: 7200.0).durationText == "2h0m")
    }

    @Test("duration property returns nil when running")
    func durationNilWhenRunning() {
        let r = ExecutionRecord(taskId: "t", taskName: "test")
        #expect(r.duration == nil)
    }

    @Test("duration property returns correct interval")
    func durationValue() {
        let r = record(duration: 42.5)
        #expect(r.duration! == 42.5)
    }
}

// MARK: - ExecutionStatus

@Suite("ExecutionStatus")
struct ExecutionStatusTests {
    @Test("Timeout status has correct rawValue")
    func timeoutRawValue() {
        #expect(ExecutionStatus.timeout.rawValue == "timeout")
    }

    @Test("All status values are distinct")
    func allDistinct() {
        let all: [ExecutionStatus] = [.running, .success, .failure, .stopped, .timeout, .pending]
        let rawValues = Set(all.map(\.rawValue))
        #expect(rawValues.count == all.count)
    }

    @Test("Timeout can be round-tripped through Codable")
    func timeoutCodable() throws {
        let record = ExecutionRecord(
            taskId: "t", taskName: "test",
            startedAt: Date(), finishedAt: Date(),
            status: .timeout
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExecutionRecord.self, from: data)
        #expect(decoded.status == .timeout)
    }
}

// MARK: - ExecutionTrigger

@Suite("ExecutionTrigger")
struct ExecutionTriggerTests {
    @Test("Trigger can be round-tripped through Codable")
    func triggerCodable() throws {
        for trigger: ExecutionTrigger in [.scheduled, .catchup, .manual] {
            let record = ExecutionRecord(
                taskId: "t", taskName: "test",
                startedAt: Date(), finishedAt: Date(),
                status: .success, trigger: trigger
            )
            let data = try JSONEncoder().encode(record)
            let decoded = try JSONDecoder().decode(ExecutionRecord.self, from: data)
            #expect(decoded.trigger == trigger)
        }
    }

    @Test("Legacy JSON without trigger field decodes as nil")
    func legacyBackwardCompatibility() throws {
        // trigger フィールドなしの既存 JSON をシミュレート
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000000",
            "taskId": "t1",
            "taskName": "test",
            "command": "echo hi",
            "working_directory": "~",
            "startedAt": "2026-01-01T00:00:00Z",
            "finishedAt": "2026-01-01T00:01:00Z",
            "exitCode": 0,
            "stdout": "",
            "stderr": "",
            "status": "success"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ExecutionRecord.self, from: Data(json.utf8))
        #expect(record.trigger == nil)
        #expect(record.status == .success)
    }

    @Test("Default trigger is nil when not specified")
    func defaultTrigger() {
        let record = ExecutionRecord(taskId: "t", taskName: "test")
        #expect(record.trigger == nil)
    }

    @Test("All trigger rawValues are distinct")
    func allDistinct() {
        let all: [ExecutionTrigger] = [.scheduled, .catchup, .manual]
        let rawValues = Set(all.map(\.rawValue))
        #expect(rawValues.count == all.count)
    }
}
