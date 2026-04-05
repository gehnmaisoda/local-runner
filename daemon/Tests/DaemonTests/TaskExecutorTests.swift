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

    @Test("Multi-line command fails if any line fails (set -e)")
    func multiLineFailsOnFirstError() {
        let executor = TaskExecutor()
        let task = makeTask(command: "exit 1\necho should-not-reach")
        let record = executor.execute(task)
        #expect(record.status == .failure)
        #expect(record.exitCode == 1)
        #expect(!record.stdout.contains("should-not-reach"))
    }

    @Test("Multi-line command succeeds only if all lines succeed")
    func multiLineAllSuccess() {
        let executor = TaskExecutor()
        let task = makeTask(command: "echo line1\necho line2")
        let record = executor.execute(task)
        #expect(record.status == .success)
        #expect(record.stdout.contains("line1"))
        #expect(record.stdout.contains("line2"))
    }

    @Test("Default timeout is used as fallback when task timeout is nil")
    func defaultTimeoutFallback() {
        let executor = TaskExecutor()
        let task = makeTask(command: "sleep 60")
        let start = Date()
        let record = executor.execute(task, defaultTimeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        #expect(record.status == .timeout)
        #expect(elapsed < 10)
    }

    @Test("Task-specific timeout takes priority over default timeout")
    func taskTimeoutOverridesDefault() {
        let executor = TaskExecutor()
        let task = makeTask(command: "sleep 60", timeout: 1)
        let start = Date()
        // defaultTimeout is very long, but task timeout (1s) should win
        let record = executor.execute(task, defaultTimeout: 300)
        let elapsed = Date().timeIntervalSince(start)
        #expect(record.status == .timeout)
        #expect(elapsed < 10)
    }

    @Test("Default timeout of 0 means no timeout for tasks without specific timeout")
    func zeroDefaultTimeoutMeansNoLimit() {
        let executor = TaskExecutor()
        let task = makeTask(command: "echo quick")
        let record = executor.execute(task, defaultTimeout: 0)
        #expect(record.status == .success)
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

        // Poll until both processes are running (up to 5 seconds)
        let deadline = Date().addingTimeInterval(5)
        while (!executor.isRunning("sa-1") || !executor.isRunning("sa-2")) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
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
            // After SIGTERM, zsh may exit as .stopped, .failure, or .timeout
            #expect(record.status != .success)
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
    @Test("Stopping a running task sets non-success status")
    func manualStop() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "ms-1", name: "ms-1", command: "sleep 60")

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var record: ExecutionRecord?

        DispatchQueue.global().async {
            record = executor.execute(task)
            semaphore.signal()
        }

        // Poll until the process is actually running (up to 5 seconds)
        let deadline = Date().addingTimeInterval(5)
        while !executor.isRunning("ms-1") && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        #expect(executor.isRunning("ms-1"))

        executor.stop("ms-1")
        semaphore.wait()

        // After SIGTERM, zsh may exit as .uncaughtSignal (→ .stopped) or
        // with a non-zero exit code (→ .failure). Either way it should not be .success.
        #expect(record?.status != .success)
        #expect(!executor.isRunning("ms-1"))
    }
}

// MARK: - Working directory

@Suite("TaskExecutor - Working directory")
struct TaskExecutorWorkingDirTests {
    @Test("Working directory is expanded from tilde")
    func tildeExpansion() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "wd-1", name: "wd-1", command: "pwd", workingDirectory: "~")
        let record = executor.execute(task)
        #expect(record.status == .success)
        let pwd = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Should be the actual home directory, not literally "~"
        #expect(!pwd.contains("~"))
        #expect(pwd == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test("Nil working directory defaults to home directory")
    func nilWorkingDir() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "wd-2", name: "wd-2", command: "pwd")
        let record = executor.execute(task)
        #expect(record.status == .success)
        let pwd = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Default is ~, which gets expanded
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(pwd == home)
    }

    @Test("Specific working directory is used")
    func specificWorkingDir() throws {
        // Create a uniquely-named temp subdirectory to avoid symlink ambiguity
        let unique = "lr-test-\(UUID().uuidString)"
        let testDir = FileManager.default.temporaryDirectory.appendingPathComponent(unique)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let executor = TaskExecutor()
        let task = TaskDefinition(id: "wd-3", name: "wd-3", command: "pwd", workingDirectory: testDir.path)
        let record = executor.execute(task)
        #expect(record.status == .success)
        let pwd = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Verify pwd ends with our unique directory name (avoids /var vs /private/var issues)
        #expect(pwd.hasSuffix(unique))
    }
}

// MARK: - Environment variables

@Suite("TaskExecutor - Environment variables")
struct TaskExecutorEnvironmentTests {
    @Test("Process inherits environment variables")
    func inheritsEnv() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "env-1", name: "env-1", command: "echo $HOME")
        let record = executor.execute(task)
        #expect(record.status == .success)
        let output = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!output.isEmpty)
        #expect(output == FileManager.default.homeDirectoryForCurrentUser.path)
    }

    @Test("PATH is available in executed commands")
    func pathAvailable() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "env-2", name: "env-2", command: "echo $PATH")
        let record = executor.execute(task)
        #expect(record.status == .success)
        let output = record.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!output.isEmpty)
        #expect(output.contains("/usr"))
    }
}

// MARK: - PATH complement

@Suite("TaskExecutor - PATH complement")
struct TaskExecutorPathComplementTests {
    @Test("Adds well-known paths to minimal PATH")
    func addsWellKnownPaths() {
        let env = TaskExecutor.complementedEnvironment([
            "HOME": "/Users/testuser",
            "PATH": "/usr/bin:/bin",
        ])
        let path = env["PATH"]!
        #expect(path.contains("/Users/testuser/.local/bin"))
        #expect(path.contains("/Users/testuser/.cargo/bin"))
        #expect(path.contains("/Users/testuser/.bun/bin"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
        // Original PATH is preserved at the end
        #expect(path.hasSuffix("/usr/bin:/bin"))
    }

    @Test("Does not duplicate existing paths")
    func noDuplicates() {
        let env = TaskExecutor.complementedEnvironment([
            "HOME": "/Users/testuser",
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        ])
        let path = env["PATH"]!
        let parts = path.components(separatedBy: ":")
        let homebrewCount = parts.filter { $0 == "/opt/homebrew/bin" }.count
        #expect(homebrewCount == 1)
    }

    @Test("Uses fallback PATH when PATH is missing")
    func fallbackPath() {
        let env = TaskExecutor.complementedEnvironment([
            "HOME": "/Users/testuser",
        ])
        let path = env["PATH"]!
        #expect(path.contains("/usr/bin"))
        #expect(path.contains("/Users/testuser/.local/bin"))
    }

    @Test("Uses NSHomeDirectory when HOME is missing")
    func fallbackHome() {
        let env = TaskExecutor.complementedEnvironment([
            "PATH": "/usr/bin:/bin",
        ])
        let path = env["PATH"]!
        let home = NSHomeDirectory()
        #expect(path.contains("\(home)/.local/bin"))
    }

    @Test("Preserves non-PATH environment variables")
    func preservesOtherVars() {
        let env = TaskExecutor.complementedEnvironment([
            "HOME": "/Users/testuser",
            "PATH": "/usr/bin",
            "LANG": "ja_JP.UTF-8",
            "EDITOR": "vim",
        ])
        #expect(env["LANG"] == "ja_JP.UTF-8")
        #expect(env["EDITOR"] == "vim")
    }
}

// MARK: - Exit code handling

@Suite("TaskExecutor - Exit codes")
struct TaskExecutorExitCodeTests {
    @Test("Successful command has exit code 0")
    func exitCodeZero() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "ec-1", name: "ec-1", command: "true")
        let record = executor.execute(task)
        #expect(record.exitCode == 0)
        #expect(record.status == .success)
    }

    @Test("Failed command has non-zero exit code")
    func exitCodeNonZero() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "ec-2", name: "ec-2", command: "exit 42")
        let record = executor.execute(task)
        #expect(record.exitCode == 42)
        #expect(record.status == .failure)
    }

    @Test("Command writing to stderr still succeeds if exit code is 0")
    func stderrWithSuccess() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "ec-3", name: "ec-3", command: "echo error >&2; exit 0")
        let record = executor.execute(task)
        #expect(record.status == .success)
        #expect(record.stderr.contains("error"))
    }
}

// MARK: - Process lifecycle

@Suite("TaskExecutor - Process lifecycle")
struct TaskExecutorLifecycleTests {
    @Test("isRunning returns false for unknown task")
    func isRunningUnknown() {
        let executor = TaskExecutor()
        #expect(!executor.isRunning("nonexistent"))
    }

    @Test("hasRunningTasks is false when no tasks are running")
    func noRunningTasks() {
        let executor = TaskExecutor()
        #expect(!executor.hasRunningTasks)
    }

    @Test("Stopping a non-existent task does not crash")
    func stopNonExistent() {
        let executor = TaskExecutor()
        executor.stop("nonexistent") // Should not crash
    }

    @Test("Record includes working directory")
    func recordWorkingDirectory() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "r-1", name: "r-1", command: "echo hi", workingDirectory: "/tmp")
        let record = executor.execute(task)
        #expect(record.workingDirectory == "/tmp")
    }

    @Test("Record includes command string")
    func recordCommand() {
        let executor = TaskExecutor()
        let task = TaskDefinition(id: "r-2", name: "r-2", command: "echo specific_command")
        let record = executor.execute(task)
        #expect(record.command == "echo specific_command")
    }

    @Test("Record has startedAt and finishedAt after execution")
    func recordTimestamps() {
        let executor = TaskExecutor()
        let before = Date()
        let task = TaskDefinition(id: "r-3", name: "r-3", command: "echo hi")
        let record = executor.execute(task)
        let after = Date()

        #expect(record.startedAt >= before)
        #expect(record.finishedAt != nil)
        #expect(record.finishedAt! <= after)
        #expect(record.finishedAt! >= record.startedAt)
    }
}
