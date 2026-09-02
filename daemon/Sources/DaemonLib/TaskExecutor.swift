import Foundation
import Core

/// シェルコマンドを実行し、結果を返す。
public final class TaskExecutor: @unchecked Sendable {
    /// 実行中プロセスの管理（タスクID → Process）
    private var runningProcesses: [String: Process] = [:]
    private let lock = NSLock()

    /// SIGKILL までの猶予時間（秒）。
    private static let killGracePeriod: TimeInterval = 3

    /// 永続化するstdout/stderrの上限。先頭2KiBと末尾を残し、過剰なAIログの肥大化を防ぐ。
    static let maxCapturedOutputBytes = 16 * 1024
    private static let capturedOutputHeadBytes = 2 * 1024

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
    public func execute(
        _ task: TaskDefinition,
        defaultTimeout: Int? = nil,
        additionalEnvironment: [String: String] = [:]
    ) -> ExecutionRecord {
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

        var environment = Self.complementedEnvironment(ProcessInfo.processInfo.environment)
        environment.merge(additionalEnvironment) { _, new in new }
        process.environment = environment

        // Pipeを終了後まで読まないと、大量出力時にバッファが埋まり子プロセスが停止する。
        // 一時ファイルへ直接流し、プロセス終了後にExecutionRecordへ取り込む。
        let outputId = UUID().uuidString
        let stdoutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-runner-\(outputId).stdout")
        let stderrURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-runner-\(outputId).stderr")
        let privateAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil, attributes: privateAttributes),
              FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: privateAttributes),
              let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
              let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path) else {
            record.stderr = "タスク出力用の一時ファイルを作成できません"
            record.exitCode = -1
            record.finishedAt = Date()
            record.status = .failure
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            return record
        }
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

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

            try? stdoutHandle.close()
            try? stderrHandle.close()
            record.stdout = Self.compactOutput(at: stdoutURL)
            record.stderr = Self.compactOutput(at: stderrURL)
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

    /// 小さい出力はそのまま、大きい出力は診断に必要な冒頭と最終結果がある末尾だけを残す。
    static func compactOutput(at url: URL, maxBytes: Int = maxCapturedOutputBytes) -> String {
        guard maxBytes > 0,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else { return "" }

        let size = fileSize.intValue
        if size <= maxBytes {
            let data = (try? Data(contentsOf: url)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }

        let headSize = min(capturedOutputHeadBytes, maxBytes / 2)
        let tailSize = maxBytes - headSize
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        let head = (try? handle.read(upToCount: headSize)) ?? Data()
        try? handle.seek(toOffset: UInt64(size - tailSize))
        let tail = (try? handle.read(upToCount: tailSize)) ?? Data()
        let omitted = max(0, size - head.count - tail.count)

        return String(decoding: head, as: UTF8.self)
            + "\n...[LocalRunner: \(omitted) bytes omitted]...\n"
            + String(decoding: tail, as: UTF8.self)
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
