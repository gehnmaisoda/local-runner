import Foundation

// MARK: - IPC Request

/// GUI → ヘルパーへのリクエスト。
public struct IPCRequest: Codable, Sendable {
    public let action: String
    public var taskId: String?
    public var limit: Int?
    public var task: TaskDefinition?
    public var settings: GlobalSettings?

    public init(
        action: String,
        taskId: String? = nil,
        limit: Int? = nil,
        task: TaskDefinition? = nil,
        settings: GlobalSettings? = nil
    ) {
        self.action = action
        self.taskId = taskId
        self.limit = limit
        self.task = task
        self.settings = settings
    }

    // ファクトリメソッド
    public static var listTasks: Self { .init(action: "list_tasks") }
    public static func runTask(_ id: String) -> Self { .init(action: "run_task", taskId: id) }
    public static func stopTask(_ id: String) -> Self { .init(action: "stop_task", taskId: id) }
    public static func getHistory(taskId: String? = nil, limit: Int = 50) -> Self {
        .init(action: "get_history", taskId: taskId, limit: limit)
    }
    public static var reload: Self { .init(action: "reload") }
    public static var getSettings: Self { .init(action: "get_settings") }
    public static func updateSettings(_ s: GlobalSettings) -> Self {
        .init(action: "update_settings", settings: s)
    }
    public static func saveTask(_ t: TaskDefinition) -> Self { .init(action: "save_task", task: t) }
    public static func deleteTask(_ id: String) -> Self { .init(action: "delete_task", taskId: id) }
    public static func toggleTask(_ id: String) -> Self { .init(action: "toggle_task", taskId: id) }
    public static var getVersion: Self { .init(action: "get_version") }
    public static var subscribe: Self { .init(action: "subscribe") }
    public static func getSystemLogs(limit: Int = 1000) -> Self { .init(action: "get_system_logs", limit: limit) }
}

// MARK: - System Log Entry

/// システムログのエントリ。
public struct LogEntry: Codable, Sendable {
    public let timestamp: Date
    public let tag: String
    public let message: String

    public init(timestamp: Date, tag: String, message: String) {
        self.timestamp = timestamp
        self.tag = tag
        self.message = message
    }
}

// MARK: - IPC Response

/// ヘルパー → GUI へのレスポンス。
public struct IPCResponse: Codable, Sendable {
    public var success: Bool
    public var error: String?
    public var tasks: [TaskStatus]?
    public var history: [ExecutionRecord]?
    public var settings: GlobalSettings?
    public var version: String?
    public var systemLogs: [LogEntry]?

    public init(
        success: Bool = true,
        error: String? = nil,
        tasks: [TaskStatus]? = nil,
        history: [ExecutionRecord]? = nil,
        settings: GlobalSettings? = nil,
        version: String? = nil,
        systemLogs: [LogEntry]? = nil
    ) {
        self.success = success
        self.error = error
        self.tasks = tasks
        self.history = history
        self.settings = settings
        self.version = version
        self.systemLogs = systemLogs
    }

    public static var ok: Self { .init() }
    public static func error(_ msg: String) -> Self { .init(success: false, error: msg) }
}

// MARK: - Task Status

/// タスク定義 + 実行状態の統合ビュー。
public struct TaskStatus: Codable, Sendable, Identifiable {
    public let task: TaskDefinition
    public var lastRun: ExecutionRecord?
    public var nextRunAt: Date?
    public var isRunning: Bool

    public var id: String { task.id }

    public init(
        task: TaskDefinition,
        lastRun: ExecutionRecord? = nil,
        nextRunAt: Date? = nil,
        isRunning: Bool = false
    ) {
        self.task = task
        self.lastRun = lastRun
        self.nextRunAt = nextRunAt
        self.isRunning = isRunning
    }
}

// MARK: - IPC Notification

/// ヘルパー → GUI へのプッシュ通知。
public struct IPCNotification: Codable, Sendable {
    public let event: String
    public var taskId: String?
    public var record: ExecutionRecord?

    public init(event: String, taskId: String? = nil, record: ExecutionRecord? = nil) {
        self.event = event
        self.taskId = taskId
        self.record = record
    }

    public static func taskStarted(_ id: String) -> Self { .init(event: "task_started", taskId: id) }
    public static func taskCompleted(_ id: String, record: ExecutionRecord) -> Self {
        .init(event: "task_completed", taskId: id, record: record)
    }
    public static var tasksChanged: Self { .init(event: "tasks_changed") }
}

// MARK: - Global Settings

/// アプリ全体の設定。
public struct GlobalSettings: Codable, Sendable, Equatable {
    public var slackBotToken: String?
    public var slackChannel: String?
    public var defaultTimeout: Int?

    public static let defaultTimeoutValue = 3600

    public init(slackBotToken: String? = nil, slackChannel: String? = nil, defaultTimeout: Int? = nil) {
        self.slackBotToken = slackBotToken
        self.slackChannel = slackChannel
        self.defaultTimeout = defaultTimeout
    }

    /// タスク個別のタイムアウトが未設定の場合に使うタイムアウト値を返す。
    public var effectiveDefaultTimeout: Int {
        defaultTimeout ?? Self.defaultTimeoutValue
    }

    enum CodingKeys: String, CodingKey {
        case slackBotToken = "slack_bot_token"
        case slackChannel = "slack_channel"
        case defaultTimeout = "default_timeout"
    }
}

// MARK: - Wire Format

/// IPC メッセージのワイヤーフォーマット。
/// 4バイトのビッグエンディアン長 + JSON データ。
public enum IPCWireFormat: Sendable {
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 型付き値を長さプレフィックス付き JSON にエンコードする。
    public static func encode<T: Encodable & Sendable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        let json = try encoder.encode(value)
        var length = UInt32(json.count).bigEndian
        var data = Data(bytes: &length, count: 4)
        data.append(json)
        return data
    }

    /// バッファから1メッセージ分を取り出す。データが不足していれば nil。
    public static func readMessage(from buffer: inout Data) -> Data? {
        guard buffer.count >= 4 else { return nil }
        // バイト単位で読み取り（アライメント非依存）
        let b0 = buffer[buffer.startIndex]
        let b1 = buffer[buffer.startIndex + 1]
        let b2 = buffer[buffer.startIndex + 2]
        let b3 = buffer[buffer.startIndex + 3]
        let length = Int(UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3))
        let totalLength = 4 + length
        guard buffer.count >= totalLength else { return nil }
        let message = buffer.subdata(in: (buffer.startIndex + 4)..<(buffer.startIndex + totalLength))
        buffer = buffer.subdata(in: (buffer.startIndex + totalLength)..<buffer.endIndex)
        return message
    }

    /// JSON データをデコードする。
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = isoFormatter.date(from: str) { return date }
            // Fallback for dates without fractional seconds
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return try decoder.decode(type, from: data)
    }
}
