import Foundation
import Core

/// シェルコマンドを実行し、結果を返す。
final class TaskExecutor: @unchecked Sendable {
    /// 実行中プロセスの管理（タスクID → Process）
    private var runningProcesses: [String: Process] = [:]
    private let lock = NSLock()

    /// タスクを実行し、完了した ExecutionRecord を返す。
    func execute(_ task: TaskDefinition) -> ExecutionRecord {
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
        process.arguments = ["-l", "-c", task.command]

        let dir = task.workingDirectory ?? "~"
        let expandedDir = NSString(string: dir).expandingTildeInPath
        process.currentDirectoryURL = URL(fileURLWithPath: expandedDir)

        // 環境変数を引き継ぐ
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        lock.withLock { runningProcesses[task.id] = process }

        defer {
            lock.withLock { runningProcesses.removeValue(forKey: task.id) }
        }

        do {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            record.stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            record.stderr = String(data: stderrData, encoding: .utf8) ?? ""
            record.exitCode = process.terminationStatus
            record.finishedAt = Date()

            if process.terminationReason == .uncaughtSignal {
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

    /// 実行中のタスクを停止する。
    func stop(_ taskId: String) {
        lock.lock()
        let process = runningProcesses[taskId]
        lock.unlock()
        process?.terminate()
    }

    /// タスクが実行中かどうか。
    func isRunning(_ taskId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningProcesses[taskId]?.isRunning ?? false
    }
}
