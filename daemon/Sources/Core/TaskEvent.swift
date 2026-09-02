import Foundation

/// Cloud Queue から受信し、イベントタスクへ渡す最小コンテキスト。
public struct TaskEvent: Sendable, Equatable {
    public let id: String
    public let topic: String
    public let payloadFile: String
    public let attempt: Int

    public init(id: String, topic: String, payloadFile: String, attempt: Int) {
        self.id = id
        self.topic = topic
        self.payloadFile = payloadFile
        self.attempt = attempt
    }

    public var environment: [String: String] {
        [
            "LR_EVENT_ID": id,
            "LR_EVENT_TOPIC": topic,
            "LR_EVENT_FILE": payloadFile,
            "LR_EVENT_ATTEMPT": String(attempt),
        ]
    }
}
