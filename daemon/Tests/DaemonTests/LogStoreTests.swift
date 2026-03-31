import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - Helpers

private func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lr-logstore-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func makeRecord(
    taskId: String = "task-1",
    status: ExecutionStatus = .success,
    startedAt: Date = Date()
) -> ExecutionRecord {
    ExecutionRecord(
        taskId: taskId,
        taskName: taskId,
        command: "echo test",
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(1),
        status: status
    )
}

// MARK: - Append and retrieval

@Suite("LogStore - append and retrieval")
struct LogStoreAppendTests {
    @Test("Appending a record makes it retrievable via history")
    func appendAndRetrieve() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let record = makeRecord()
        store.append(record)

        let history = store.history(taskId: "task-1")
        #expect(history.count == 1)
        #expect(history[0].id == record.id)
        #expect(history[0].status == .success)
    }

    @Test("Appending multiple records for the same task preserves order")
    func appendMultiple() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let r1 = makeRecord(startedAt: Date())
        let r2 = makeRecord(startedAt: Date().addingTimeInterval(1))
        let r3 = makeRecord(startedAt: Date().addingTimeInterval(2))
        store.append(r1)
        store.append(r2)
        store.append(r3)

        let history = store.history(taskId: "task-1")
        #expect(history.count == 3)
        #expect(history[0].id == r1.id)
        #expect(history[2].id == r3.id)
    }

    @Test("Records for different tasks are stored separately")
    func differentTasks() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        store.append(makeRecord(taskId: "a"))
        store.append(makeRecord(taskId: "b"))
        store.append(makeRecord(taskId: "a"))

        #expect(store.history(taskId: "a").count == 2)
        #expect(store.history(taskId: "b").count == 1)
        #expect(store.history(taskId: "c").count == 0)
    }

    @Test("lastRecord returns the most recent record")
    func lastRecord() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let r1 = makeRecord(startedAt: Date())
        let r2 = makeRecord(startedAt: Date().addingTimeInterval(1))
        store.append(r1)
        store.append(r2)

        #expect(store.lastRecord(taskId: "task-1")?.id == r2.id)
    }

    @Test("lastRecord returns nil for unknown task")
    func lastRecordUnknown() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        #expect(store.lastRecord(taskId: "nonexistent") == nil)
    }
}

// MARK: - Update

@Suite("LogStore - update")
struct LogStoreUpdateTests {
    @Test("Updating a record modifies it in place")
    func updateRecord() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        var record = makeRecord(status: .running)
        store.append(record)

        record.status = .success
        record.finishedAt = Date()
        record.exitCode = 0
        store.update(record)

        let history = store.history(taskId: "task-1")
        #expect(history.count == 1)
        #expect(history[0].status == .success)
        #expect(history[0].exitCode == 0)
    }

    @Test("Updating a non-existent record does nothing")
    func updateNonExistent() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let record = makeRecord()
        store.update(record) // No crash, no-op
        #expect(store.history(taskId: "task-1").isEmpty)
    }
}

// MARK: - Delete

@Suite("LogStore - deleteHistory")
struct LogStoreDeleteTests {
    @Test("deleteHistory removes all records for a task")
    func deleteHistory() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        store.append(makeRecord(taskId: "task-1"))
        store.append(makeRecord(taskId: "task-1"))
        store.append(makeRecord(taskId: "task-2"))

        store.deleteHistory(taskId: "task-1")

        #expect(store.history(taskId: "task-1").isEmpty)
        #expect(store.history(taskId: "task-2").count == 1)
    }

    @Test("deleteHistory removes the JSON file on disk")
    func deleteHistoryFile() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        store.append(makeRecord(taskId: "task-1"))

        let filePath = dir.appendingPathComponent("task-1.json").path
        #expect(FileManager.default.fileExists(atPath: filePath))

        store.deleteHistory(taskId: "task-1")
        #expect(!FileManager.default.fileExists(atPath: filePath))
    }
}

// MARK: - Cache bounds

@Suite("LogStore - cache bounds")
struct LogStoreCacheBoundsTests {
    @Test("Cache is trimmed to maxCacheRecordsPerTask on append")
    func cacheTrimmed() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let limit = LogStore.maxCacheRecordsPerTask

        // Append more records than the limit
        for i in 0..<(limit + 50) {
            store.append(makeRecord(
                taskId: "task-1",
                startedAt: Date().addingTimeInterval(Double(i))
            ))
        }

        let history = store.history(taskId: "task-1", limit: limit + 100)
        #expect(history.count == limit)
    }

    @Test("After trimming, the most recent records are kept")
    func trimKeepsRecent() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let limit = LogStore.maxCacheRecordsPerTask
        let total = limit + 10
        var lastId: UUID?

        for i in 0..<total {
            let r = makeRecord(taskId: "t", startedAt: Date().addingTimeInterval(Double(i)))
            store.append(r)
            if i == total - 1 { lastId = r.id }
        }

        let last = store.lastRecord(taskId: "t")
        #expect(last?.id == lastId)
    }
}

// MARK: - History queries

@Suite("LogStore - history queries")
struct LogStoreHistoryQueryTests {
    @Test("history respects limit parameter")
    func historyLimit() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        for i in 0..<20 {
            store.append(makeRecord(startedAt: Date().addingTimeInterval(Double(i))))
        }

        let limited = store.history(taskId: "task-1", limit: 5)
        #expect(limited.count == 5)
    }

    @Test("history returns the most recent records when limited")
    func historyReturnsLatest() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        var ids: [UUID] = []
        for i in 0..<10 {
            let r = makeRecord(startedAt: Date().addingTimeInterval(Double(i)))
            store.append(r)
            ids.append(r.id)
        }

        let limited = store.history(taskId: "task-1", limit: 3)
        #expect(limited.count == 3)
        #expect(limited[0].id == ids[7])
        #expect(limited[2].id == ids[9])
    }

    @Test("timeline returns records from all tasks sorted by date descending")
    func timeline() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let base = Date()
        store.append(makeRecord(taskId: "a", startedAt: base))
        store.append(makeRecord(taskId: "b", startedAt: base.addingTimeInterval(2)))
        store.append(makeRecord(taskId: "c", startedAt: base.addingTimeInterval(1)))

        let timeline = store.timeline(limit: 10)
        #expect(timeline.count == 3)
        // Newest first
        #expect(timeline[0].taskId == "b")
        #expect(timeline[1].taskId == "c")
        #expect(timeline[2].taskId == "a")
    }

    @Test("timeline respects limit")
    func timelineLimit() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        for i in 0..<10 {
            store.append(makeRecord(taskId: "t\(i)", startedAt: Date().addingTimeInterval(Double(i))))
        }

        let timeline = store.timeline(limit: 3)
        #expect(timeline.count == 3)
    }
}

// MARK: - Persistence

@Suite("LogStore - persistence across instances")
struct LogStorePersistenceTests {
    @Test("Records persist to disk and can be loaded by a new instance")
    func persistenceRoundtrip() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = LogStore(directory: dir)
        let record = makeRecord(taskId: "persist-test")
        store1.append(record)

        // Create a new instance pointing to the same directory
        let store2 = LogStore(directory: dir)
        let history = store2.history(taskId: "persist-test")
        #expect(history.count == 1)
        #expect(history[0].id == record.id)
    }
}

// MARK: - Corrupt/malformed JSON

@Suite("LogStore - corrupt JSON handling")
struct LogStoreCorruptJsonTests {
    @Test("Malformed JSON file is gracefully skipped")
    func malformedJson() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write garbage to a JSON file
        let badFile = dir.appendingPathComponent("bad-task.json")
        try! "not valid json {{{".write(to: badFile, atomically: true, encoding: .utf8)

        let store = LogStore(directory: dir)
        let history = store.history(taskId: "bad-task")
        #expect(history.isEmpty)
    }

    @Test("Empty JSON file is gracefully skipped")
    func emptyJsonFile() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let emptyFile = dir.appendingPathComponent("empty-task.json")
        try! "".write(to: emptyFile, atomically: true, encoding: .utf8)

        let store = LogStore(directory: dir)
        let history = store.history(taskId: "empty-task")
        #expect(history.isEmpty)
    }

    @Test("Valid and corrupt files coexist; valid ones are loaded")
    func mixedFiles() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a valid record first via LogStore
        let store1 = LogStore(directory: dir)
        store1.append(makeRecord(taskId: "good-task"))

        // Write corrupt file manually
        let badFile = dir.appendingPathComponent("bad-task.json")
        try! "corrupted".write(to: badFile, atomically: true, encoding: .utf8)

        // Load from a new instance
        let store2 = LogStore(directory: dir)
        #expect(store2.history(taskId: "good-task").count == 1)
        #expect(store2.history(taskId: "bad-task").isEmpty)
    }

    @Test("Non-JSON files are ignored")
    func nonJsonFilesIgnored() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let txtFile = dir.appendingPathComponent("notes.txt")
        try! "some text".write(to: txtFile, atomically: true, encoding: .utf8)

        let store = LogStore(directory: dir)
        // Should load without error, no records
        #expect(store.timeline(limit: 100).isEmpty)
    }
}

// MARK: - Concurrent access

@Suite("LogStore - concurrent access")
struct LogStoreConcurrentTests {
    @Test("Concurrent appends do not crash")
    func concurrentAppends() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        let group = DispatchGroup()
        let iterations = 100

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                store.append(makeRecord(
                    taskId: "task-\(i % 5)",
                    startedAt: Date().addingTimeInterval(Double(i))
                ))
                group.leave()
            }
        }

        group.wait()

        // Verify all records were stored
        var total = 0
        for t in 0..<5 {
            total += store.history(taskId: "task-\(t)", limit: 1000).count
        }
        #expect(total == iterations)
    }

    @Test("Concurrent reads and writes do not crash")
    func concurrentReadsAndWrites() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LogStore(directory: dir)
        // Pre-populate some data
        for i in 0..<10 {
            store.append(makeRecord(taskId: "t", startedAt: Date().addingTimeInterval(Double(i))))
        }

        let group = DispatchGroup()
        for i in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    store.append(makeRecord(taskId: "t", startedAt: Date().addingTimeInterval(Double(i + 100))))
                } else {
                    _ = store.history(taskId: "t", limit: 5)
                }
                group.leave()
            }
        }

        group.wait()
        // Just verify no crash
        let history = store.history(taskId: "t", limit: 1000)
        #expect(history.count >= 10)
    }
}
