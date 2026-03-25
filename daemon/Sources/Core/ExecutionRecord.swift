import Foundation

/// タスク実行結果のステータス。
public enum ExecutionStatus: String, Codable, Sendable {
    case running
    case success
    case failure
    case stopped
}

/// タスク1回分の実行記録。
public struct ExecutionRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let taskId: String
    public let taskName: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
    public var status: ExecutionStatus

    public init(
        id: UUID = UUID(),
        taskId: String,
        taskName: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        exitCode: Int32? = nil,
        stdout: String = "",
        stderr: String = "",
        status: ExecutionStatus = .running
    ) {
        self.id = id
        self.taskId = taskId
        self.taskName = taskName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
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
        if d < 3600 {
            return String(format: "%.0fm%.0fs", d / 60, d.truncatingRemainder(dividingBy: 60))
        }
        return String(format: "%.0fh%.0fm", d / 3600, (d / 60).truncatingRemainder(dividingBy: 60))
    }
}
