import Foundation

/// タスク実行結果のステータス。
public enum ExecutionStatus: String, Codable, Sendable {
    case running
    case success
    case failure
    case stopped
    case timeout
    case pending
}

/// タスク実行のトリガー種別。
public enum ExecutionTrigger: String, Codable, Sendable {
    case scheduled  // 通常のスケジュール実行
    case catchup    // スリープ復帰後のキャッチアップ実行
    case manual     // 手動実行 (run_task)
}

/// タスク1回分の実行記録。
public struct ExecutionRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let taskId: String
    public let taskName: String
    public let command: String
    public let workingDirectory: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var status: ExecutionStatus
    /// 実行トリガー。既存レコード（フィールドなし）との後方互換のため Optional。nil は .scheduled 相当。
    public var trigger: ExecutionTrigger?

    enum CodingKeys: String, CodingKey {
        case id, taskId, taskName, command, startedAt, finishedAt, exitCode, stdout, stderr, status, trigger
        case workingDirectory = "working_directory"
    }

    public init(
        id: UUID = UUID(),
        taskId: String,
        taskName: String,
        command: String = "",
        workingDirectory: String = "~",
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        status: ExecutionStatus = .running,
        trigger: ExecutionTrigger? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.command = command
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.trigger = trigger
    }

    /// 実行時間（秒）。実行中の場合は nil。
    public var duration: TimeInterval? {
        guard let finished = finishedAt else { return nil }
        return finished.timeIntervalSince(startedAt)
    }

    /// 実行時間の表示テキスト。
    public var durationText: String {
        guard let d = duration else { return "—" }
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        if d < 60 { return String(format: "%.1fs", d) }
        let total = Int(d)
        if d < 3600 {
            return "\(total / 60)m\(total % 60)s"
        }
        return "\(total / 3600)h\((total % 3600) / 60)m"
    }
}
