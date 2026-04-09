import Foundation
import Core

/// シェルコマンドを実行し、結果を返す。
public final class TaskExecutor: @unchecked Sendable {
    /// 実行中プロセスの管理（タスクID → Process）
    private var runningProcesses: [String: Process] = [:]
    private let lock = NSLock()

    /// SIGKILL までの猶予時間（秒）。
    private static let killGracePeriod: TimeInterval = 3

    /// LaunchAgent の最小 PATH にユーザーツールの代表的パスを補完する
    static let wellKnownPaths: [String] = [
        "/.local/bin",
        "/.cargo/bin",
        "/.bun/bin",
        "/.deno/bin",
        "/.volta/bin",
        "/.nvm/versions/node/default/bin",
        "/.pyenv/shims",
        "/.rbenv/shims",
        "/.goenv/shims",
    ]

    static let systemPaths: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
    ]

    /// 環境変数を引き継ぎつつ、PATH を補完した環境変数辞書を返す。
    static func complementedEnvironment(_ base: [String: String]) -> [String: String] {
        var env = base
        let home = env["HOME"] ?? NSHomeDirectory()
        let extraPaths = wellKnownPaths.map { home + $0 } + systemPaths
        let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let currentParts = Set(currentPath.components(separatedBy: ":"))
        let newParts = extraPaths.filter { !currentParts.contains($0) }
        env["PATH"] = (newParts + [currentPath]).joined(separator: ":")
        return env
    }

    public init() {}

    /// タスクを実行し、完了した ExecutionRecord を返す。
    /// `defaultTimeout` はタスク個別のタイムアウトが未設定の場合のフォールバック。
    public func execute(_ task: TaskDefinition, defaultTimeout: Int? = nil) -> ExecutionRecord {
        var record = ExecutionRecord(
            taskId: task.id,
            taskName: task.name,
            command: task.command,
            workingDirectory: task.workingDirectory ?? "~",
            startedAt: Date(),
            status: .running
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // set -e: 途中のコマンドが失敗したら即終了
        // set -o pipefail: パイプライン中の失敗も検知
        process.arguments = ["-l", "-c", "source ~/.zshrc 2>/dev/null\nset -eo pipefail\n" + task.command]

        let dir = task.workingDirectory ?? "~"
        let expandedDir = NSString(string: dir).expandingTildeInPath
        process.currentDirectoryURL = URL(fileURLWithPath: expandedDir)

        process.environment = Self.complementedEnvironment(ProcessInfo.processInfo.environment)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        lock.withLock { runningProcesses[task.id] = process }

        defer {
            lock.withLock { _ = runningProcesses.removeValue(forKey: task.id) }
        }

        do {
            try process.run()

            var timedOut = false
            let effectiveTimeout = task.timeout ?? defaultTimeout
            if let timeout = effectiveTimeout, timeout > 0 {
                timedOut = waitWithTimeout(process: process, timeout: TimeInterval(timeout))
            } else {
                process.waitUntilExit()
            }

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            record.stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            record.stderr = String(data: stderrData, encoding: .utf8) ?? ""
            record.exitCode = process.terminationStatus
            record.finishedAt = Date()

            if timedOut {
                record.status = .timeout
            } else if process.terminationReason == .uncaughtSignal {
                record.status = .stopped
            } else if process.terminationStatus == 0 {
                record.status = .success
            } else {
                record.status = .failure
            }
        } catch {
            record.stderr = error.localizedDescription
            record.exitCode = -1
            record.finishedAt = Date()
            record.status = .failure
        }

        return record
    }

    /// タイムアウト付きでプロセスの完了を待つ。タイムアウトした場合は SIGTERM → SIGKILL で停止し true を返す。
    private func waitWithTimeout(process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            // SIGTERM で停止を試みる
            process.terminate()

            let killResult = semaphore.wait(timeout: .now() + Self.killGracePeriod)
            if killResult == .timedOut {
                // 猶予期間後も終了しなければ SIGKILL
                kill(process.processIdentifier, SIGKILL)
                semaphore.wait()
            }
            return true
        }
        return false
    }

    /// 実行中のタスクを停止する。
    public func stop(_ taskId: String) {
        lock.lock()
        let process = runningProcesses[taskId]
        lock.unlock()
        process?.terminate()
    }

    /// タスクが実行中かどうか。
    public func isRunning(_ taskId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningProcesses[taskId]?.isRunning ?? false
    }

    /// 全実行中プロセスを停止し、完了を待つ。
    public func stopAll(timeout: TimeInterval = 5) {
        lock.lock()
        let processes = Array(runningProcesses.values)
        lock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }

        // デッドラインまでポーリングして全プロセスの終了を待つ
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if processes.allSatisfy({ !$0.isRunning }) { break }
            Thread.sleep(forTimeInterval: 0.1)
        }

        // タイムアウト後もまだ生きているプロセスは SIGKILL
        for process in processes where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// 実行中タスクがあるかどうか。
    public var hasRunningTasks: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !runningProcesses.isEmpty
    }
}
