import Testing
import Foundation
@testable import Core
@testable import DaemonLib

private final class MockQueueTransport: QueueTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [QueueMessage]
    private(set) var acknowledged: [String] = []
    private(set) var retried: [String] = []
    let acked = DispatchSemaphore(value: 0)
    let retryRequested = DispatchSemaphore(value: 0)

    init(messages: [QueueMessage]) {
        self.messages = messages
    }

    func pull(completion: @escaping @Sendable (Result<[QueueMessage], Error>) -> Void) {
        let next = lock.withLock { messages.isEmpty ? [] : [messages.removeFirst()] }
        completion(.success(next))
    }

    func acknowledge(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.withLock { acknowledged.append(leaseId) }
        completion(.success(()))
        acked.signal()
    }

    func retry(leaseId: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.withLock { retried.append(leaseId) }
        completion(.success(()))
        retryRequested.signal()
    }
}

private func queueTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("local-runner-queue-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func queueMessage(eventId: String = "demo:1") -> QueueMessage {
    let body = """
    {"version":1,"id":"\(eventId)","topic":"demo.completed","occurred_at":"2026-09-02T00:00:00Z","payload":{"value":1}}
    """
    return QueueMessage(body: body, id: "queue-message", attempts: 1, leaseId: "lease-1", contentType: "text")
}

@Suite("ProcessedEventStore")
struct ProcessedEventStoreTests {
    @Test("Successful IDs survive store recreation")
    func persists() throws {
        let directory = try queueTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("processed.json")
        let first = ProcessedEventStore(fileURL: file)
        try first.markProcessed("demo:1")
        let second = ProcessedEventStore(fileURL: file)

        #expect(second.contains("demo:1"))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}

@Suite("QueueConsumer")
struct QueueConsumerTests {
    private let configuration = QueueConfiguration(
        accountId: "account", queueId: "queue", apiToken: "token", pollIntervalSeconds: 5
    )

    @Test("Successful event is persisted and acknowledged")
    func success() throws {
        let directory = try queueTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProcessedEventStore(fileURL: directory.appendingPathComponent("processed.json"))
        let transport = MockQueueTransport(messages: [queueMessage()])
        let handled = DispatchSemaphore(value: 0)
        let consumer = QueueConsumer(
            configuration: configuration, transport: transport, processedStore: store,
            payloadDirectory: directory
        ) { event, completion in
            #expect(event.id == "demo:1")
            #expect(event.topic == "demo.completed")
            #expect(FileManager.default.fileExists(atPath: event.payloadFile))
            handled.signal()
            completion(true)
        }

        consumer.start()
        #expect(handled.wait(timeout: .now() + 2) == .success)
        #expect(transport.acked.wait(timeout: .now() + 2) == .success)
        consumer.stop()

        #expect(store.contains("demo:1"))
        #expect(transport.acknowledged == ["lease-1"])
        #expect(transport.retried.isEmpty)
    }

    @Test("Failed task requests a retry and does not mark the ID")
    func failure() throws {
        let directory = try queueTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProcessedEventStore(fileURL: directory.appendingPathComponent("processed.json"))
        let transport = MockQueueTransport(messages: [queueMessage()])
        let consumer = QueueConsumer(
            configuration: configuration, transport: transport, processedStore: store,
            payloadDirectory: directory
        ) { _, completion in completion(false) }

        consumer.start()
        #expect(transport.retryRequested.wait(timeout: .now() + 2) == .success)
        consumer.stop()

        #expect(!store.contains("demo:1"))
        #expect(transport.retried == ["lease-1"])
    }

    @Test("Already processed event is acknowledged without running the task")
    func duplicate() throws {
        let directory = try queueTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProcessedEventStore(fileURL: directory.appendingPathComponent("processed.json"))
        try store.markProcessed("demo:1")
        let transport = MockQueueTransport(messages: [queueMessage()])
        let consumer = QueueConsumer(
            configuration: configuration, transport: transport, processedStore: store,
            payloadDirectory: directory
        ) { _, _ in Issue.record("duplicate event must not run") }

        consumer.start()
        #expect(transport.acked.wait(timeout: .now() + 2) == .success)
        consumer.stop()
        #expect(transport.acknowledged == ["lease-1"])
    }

    @Test("JSON pull bodies are base64 decoded")
    func base64JSON() throws {
        let raw = Data("{\"id\":\"demo:1\",\"topic\":\"demo.completed\"}".utf8)
        let message = QueueMessage(
            body: raw.base64EncodedString(), id: "q", attempts: 1,
            leaseId: "lease", contentType: "json"
        )
        #expect(try QueueConsumer.decodeBody(message) == raw)
    }
}
