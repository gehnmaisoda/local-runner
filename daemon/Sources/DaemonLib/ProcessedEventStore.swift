import Foundation
import Core

/// 成功済みイベントIDを再起動後も保持する、最小の重複排除ストア。
public final class ProcessedEventStore: @unchecked Sendable {
    private let fileURL: URL
    private let retention: TimeInterval
    private let maximumEntries: Int
    private let lock = NSLock()
    private var entries: [String: TimeInterval]

    public init(
        fileURL: URL = ConfigPaths.processedEventsFile,
        retention: TimeInterval = 30 * 24 * 60 * 60,
        maximumEntries: Int = 10_000
    ) {
        self.fileURL = fileURL
        self.retention = retention
        self.maximumEntries = maximumEntries
        self.entries = Self.load(from: fileURL)
        pruneLocked(now: Date().timeIntervalSince1970)
    }

    public func contains(_ eventId: String) -> Bool {
        lock.withLock { entries[eventId] != nil }
    }

    public func markProcessed(_ eventId: String, at date: Date = Date()) throws {
        try lock.withLock {
            let previous = entries
            entries[eventId] = date.timeIntervalSince1970
            pruneLocked(now: date.timeIntervalSince1970)
            do {
                try persistLocked()
            } catch {
                entries = previous
                throw error
            }
        }
    }

    private static func load(from url: URL) -> [String: TimeInterval] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func pruneLocked(now: TimeInterval) {
        let cutoff = now - retention
        entries = entries.filter { $0.value >= cutoff }
        if entries.count > maximumEntries {
            let keep = entries.sorted { $0.value > $1.value }.prefix(maximumEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func persistLocked() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
