import Foundation
import Core

public enum QueueEventError: Error, CustomStringConvertible {
    case invalidBody
    case invalidEnvelope

    public var description: String {
        switch self {
        case .invalidBody: return "Queue message body をJSONとして読み取れません"
        case .invalidEnvelope: return "Queue event には空でない id と topic が必要です"
        }
    }
}

/// 1本の共有Queueを順番にpullし、ローカルタスクの完了後にackする。
public final class QueueConsumer: @unchecked Sendable {
    public typealias EventHandler = @Sendable (TaskEvent, @escaping @Sendable (Bool) -> Void) -> Void

    private let configurationURL: URL
    private let processedStore: ProcessedEventStore
    private let payloadDirectory: URL
    private let eventHandler: EventHandler
    private let stateQueue = DispatchQueue(label: "com.gehnmaisoda.local-runner.queue-consumer")
    private var transport: QueueTransporting?
    private var configuration: QueueConfiguration?
    private var isStopped = true

    public init(
        configurationURL: URL = ConfigPaths.queueConfigurationFile,
        processedStore: ProcessedEventStore = ProcessedEventStore(),
        payloadDirectory: URL = ConfigPaths.eventPayloadsDirectory,
        eventHandler: @escaping EventHandler
    ) {
        self.configurationURL = configurationURL
        self.processedStore = processedStore
        self.payloadDirectory = payloadDirectory
        self.eventHandler = eventHandler
    }

    /// テスト用。ネットワークtransportを差し替える。
    init(
        configuration: QueueConfiguration,
        transport: QueueTransporting,
        processedStore: ProcessedEventStore,
        payloadDirectory: URL,
        eventHandler: @escaping EventHandler
    ) {
        self.configurationURL = ConfigPaths.queueConfigurationFile
        self.configuration = configuration
        self.transport = transport
        self.processedStore = processedStore
        self.payloadDirectory = payloadDirectory
        self.eventHandler = eventHandler
    }

    public func start() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            if self.configuration == nil {
                guard let configuration = self.loadConfiguration() else { return }
                self.configuration = configuration
                self.transport = CloudflareQueueTransport(configuration: configuration)
            }
            self.isStopped = false
            Log.info("Queue", "共有QueueのHTTP Pullを開始しました")
            self.schedulePull(after: 0)
        }
    }

    public func stop() {
        stateQueue.sync { isStopped = true }
    }

    private func loadConfiguration() -> QueueConfiguration? {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            Log.info("Queue", "queue.json がないためQueue consumerは無効です")
            return nil
        }
        do {
            let data = try Data(contentsOf: configurationURL)
            let config = try JSONDecoder().decode(QueueConfiguration.self, from: data)
            guard config.isValid else {
                Log.info("Queue", "queue.json の account_id / queue_id / api_token を確認してください")
                return nil
            }
            return config
        } catch {
            Log.info("Queue", "queue.json の読み込みに失敗: \(error.localizedDescription)")
            return nil
        }
    }

    private func schedulePull(after delay: TimeInterval) {
        guard !isStopped else { return }
        stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pullOnce()
        }
    }

    private func pullOnce() {
        guard !isStopped, let transport, let configuration else { return }
        transport.pull { [weak self] result in
            guard let consumer = self else { return }
            consumer.stateQueue.async {
                guard !consumer.isStopped else { return }
                switch result {
                case .failure(let error):
                    Log.info("Queue", "pull失敗: \(error)")
                    consumer.schedulePull(after: max(60, configuration.effectivePollInterval))
                case .success(let messages):
                    guard let message = messages.first else {
                        consumer.schedulePull(after: configuration.effectivePollInterval)
                        return
                    }
                    consumer.process(message)
                }
            }
        }
    }

    private func process(_ message: QueueMessage) {
        do {
            let rawData = try Self.decodeBody(message)
            let descriptor = try Self.parseEnvelope(rawData)

            if processedStore.contains(descriptor.id) {
                Log.info("Queue", "重複イベントをack: \(descriptor.id)")
                acknowledge(message)
                return
            }

            let payloadURL = payloadDirectory
                .appendingPathComponent("\(UUID().uuidString).json")
            try rawData.write(to: payloadURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: payloadURL.path)

            let event = TaskEvent(
                id: descriptor.id,
                topic: descriptor.topic,
                payloadFile: payloadURL.path,
                attempt: message.attempts
            )
            Log.info("Queue", "イベント受信: \(event.topic) / \(event.id) (attempt \(event.attempt))")
            eventHandler(event) { [weak self] succeeded in
                guard let consumer = self else { return }
                consumer.stateQueue.async {
                    try? FileManager.default.removeItem(at: payloadURL)
                    guard !consumer.isStopped else { return }

                    if succeeded {
                        do {
                            try consumer.processedStore.markProcessed(event.id)
                            consumer.acknowledge(message)
                        } catch {
                            Log.info("Queue", "重複排除IDの保存に失敗: \(error.localizedDescription)")
                            consumer.retry(message)
                        }
                    } else {
                        consumer.retry(message)
                    }
                }
            }
        } catch {
            Log.info("Queue", "イベントを処理できないため再試行: \(error)")
            retry(message)
        }
    }

    private func acknowledge(_ message: QueueMessage) {
        guard let transport, let configuration else { return }
        transport.acknowledge(leaseId: message.leaseId) { [weak self] result in
            guard let consumer = self else { return }
            consumer.stateQueue.async {
                guard !consumer.isStopped else { return }
                if case .failure(let error) = result {
                    Log.info("Queue", "ack失敗（visibility timeout後に再配信）: \(error)")
                }
                consumer.schedulePull(after: configuration.effectivePollInterval)
            }
        }
    }

    private func retry(_ message: QueueMessage) {
        guard let transport, let configuration else { return }
        transport.retry(leaseId: message.leaseId) { [weak self] result in
            guard let consumer = self else { return }
            consumer.stateQueue.async {
                guard !consumer.isStopped else { return }
                if case .failure(let error) = result {
                    Log.info("Queue", "retry指定失敗（visibility timeout後に再配信）: \(error)")
                }
                consumer.schedulePull(after: configuration.effectivePollInterval)
            }
        }
    }

    static func decodeBody(_ message: QueueMessage) throws -> Data {
        if message.contentType == "json" || message.contentType == "bytes" {
            guard let data = Data(base64Encoded: message.body) else { throw QueueEventError.invalidBody }
            return data
        }
        guard let data = message.body.data(using: .utf8) else { throw QueueEventError.invalidBody }
        return data
    }

    static func parseEnvelope(_ data: Data) throws -> (id: String, topic: String) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let topic = object["topic"] as? String, !topic.isEmpty else {
            throw QueueEventError.invalidEnvelope
        }
        return (id, topic)
    }
}
