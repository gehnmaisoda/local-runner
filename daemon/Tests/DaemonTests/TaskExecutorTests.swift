import Testing
import Foundation
@testable import Core
@testable import DaemonLib

@Suite("TaskExecutor - Timeout")
struct TaskExecutorTimeoutTests {
    private func makeTask(
        id: String = "test-timeout",
        command: String,
        timeout: Int? = nil
    ) -> TaskDefinition {
        TaskDefinition(id: id, name: id, command: command, timeout: timeout)
    }

    @Test("Task without timeout completes normally")
    func noTimeout() {
        let executor = TaskExecutor()
        let task = makeTask(command: "echo hello")
        let record = executor.execute(task)
        #expect(record.status == .success)
        #expect(record.stdout.contains("hello"))
    }

    @Test("Task that finishes before timeout gets success status")
    func finishesBeforeTimeout() {
        let executor = TaskExecutor()
        let task = makeTask(command: "echo fast", timeout: 10)
        let record = executor.execute(task)
        #expect(record.status == .success)
        #expect(record.stdout.contains("fast"))
    }

    @Test("Task that exceeds timeout gets timeout status")
    func exceedsTimeout() {
        let executor = TaskExecutor()
        let task = makeTask(command: "sleep 60", timeout: 1)
        let start = Date()
        let record = executor.execute(task)
        let elapsed = Date().timeIntervalSince(start)
        #expect(record.status == .timeout)
        #expect(record.finishedAt != nil)
        // Should have terminated within reasonable time (timeout + kill grace)
        #expect(elapsed < 10)
    }

    @Test("Timeout of 0 means no timeout")
    func zeroTimeoutMeansNoLimit() {
        let executor = TaskExecutor()
        let task = makeTask(command: "echo zero", timeout: 0)
        let record = executor.execute(task)
        #expect(record.status == .success)
    }

    @Test("Failed task with timeout set still gets failure status when it fails before timeout")
    func failureBeforeTimeout() {
        let executor = TaskExecutor()
        let task = makeTask(command: "exit 1", timeout: 10)
        let record = executor.execute(task)
        #expect(record.status == .failure)
        #expect(record.exitCode == 1)
    }
}

@Suite("TaskExecutor - stopAll")
struct TaskExecutorStopAllTests {
    @Test("stopAll terminates running processes")
    func stopAllTerminates() {
        let executor = TaskExecutor()
        let task1 = TaskDefinition(id: "sa-1", name: "sa-1", command: "sleep 60")
        let task2 = TaskDefinition(id: "sa-2", name: "sa-2", command: "sleep 60")

        // Start tasks in background threads
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var results: [ExecutionRecord] = []
        let lock = NSLock()

        for task in [task1, task2] {
            DispatchQueue.global().async {
                let record = executor.execute(task)
                lock.withLock { results.append(record) }
                semaphore.signal()
            }
        }

        // Wait for processes to start
        Thread.sleep(forTimeInterval: 0.5)

        // Verify they are running
        #expect(executor.isRunning("sa-1"))
        #expect(executor.isRunning("sa-2"))

        // Stop all
        executor.stopAll(timeout: 2)

        // Wait for background tasks to complete
        semaphore.wait()
        semaphore.wait()

        // Verify all stopped
        #expect(!executor.isRunning("sa-1"))
        #expect(!executor.isRunning("sa-2"))
        #expect(results.count == 2)
        for record in results {
            #expect(record.status == .stopped || record.status == .timeout)
        }
    }

    @Test("stopAll on empty executor does nothing")
    func stopAllEmpty() {
        let executor = TaskExecutor()
        executor.stopAll(timeout: 1)
        #expect(!executor.hasRunningTasks)
    }
}

@Suite("TaskExecutor - Manual stop")
struct TaskExecutorManualStopTests {
    @Test("Stopping a running task sets stopped status")
    func manualStop() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "ms-1", name: "ms-1", command: "sleep 60")

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var record: ExecutionRecord?

        DispatchQueue.global().async {
            record = executor.execute(task)
            semaphore.signal()
        }

        Thread.sleep(forTimeInterval: 0.5)
        #expect(executor.isRunning("ms-1"))

        executor.stop("ms-1")
        semaphore.wait()

        #expect(record?.status == .stopped)
        #expect(!executor.isRunning("ms-1"))
    }
}
