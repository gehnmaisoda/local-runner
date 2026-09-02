import Foundation

/// Cloudflare Queues HTTP Pull consumer のローカル接続情報。
/// `~/Library/Application Support/LocalRunner/queue.json` から読み込む。
public struct QueueConfiguration: Codable, Sendable, Equatable {
    public let accountId: String
    public let queueId: String
    public let apiToken: String
    public var pollIntervalSeconds: Int?
    public var visibilityTimeoutSeconds: Int?
    public var retryDelaySeconds: Int?

    public init(
        accountId: String,
        queueId: String,
        apiToken: String,
        pollIntervalSeconds: Int? = nil,
        visibilityTimeoutSeconds: Int? = nil,
        retryDelaySeconds: Int? = nil
    ) {
        self.accountId = accountId
        self.queueId = queueId
        self.apiToken = apiToken
        self.pollIntervalSeconds = pollIntervalSeconds
        self.visibilityTimeoutSeconds = visibilityTimeoutSeconds
        self.retryDelaySeconds = retryDelaySeconds
    }

    public var effectivePollInterval: TimeInterval {
        TimeInterval(max(5, pollIntervalSeconds ?? 15))
    }

    public var effectiveVisibilityTimeoutMilliseconds: Int {
        min(43_200_000, max(30_000, (visibilityTimeoutSeconds ?? 7_200) * 1_000))
    }

    public var effectiveRetryDelay: Int {
        min(43_200, max(0, retryDelaySeconds ?? 60))
    }

    public var isValid: Bool {
        !accountId.isEmpty && !queueId.isEmpty && !apiToken.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case queueId = "queue_id"
        case apiToken = "api_token"
        case pollIntervalSeconds = "poll_interval_seconds"
        case visibilityTimeoutSeconds = "visibility_timeout_seconds"
        case retryDelaySeconds = "retry_delay_seconds"
    }
}
