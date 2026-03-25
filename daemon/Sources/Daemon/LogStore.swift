import Foundation
import Core

/// 実行ログの永続化とクエリを担当する。
/// ログは ~/Library/Application Support/LocalRunner/logs/ にタスクIDごとの JSON ファイルとして保存される。
final class LogStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    /// タスクID → 実行履歴（メモリキャッシュ）
    private var cache: [String: [ExecutionRecord]] = [:]
    private var loaded = false

    init(directory: URL = ConfigPaths.logsDirectory) {
        self.directory = directory
    }

    // MARK: - 書き込み

    /// 実行記録を追加する。
    func append(_ record: ExecutionRecord) {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        var records = cache[record.taskId] ?? []
        records.append(record)
        cache[record.taskId] = records
        saveTaskLog(taskId: record.taskId, records: records)
    }

    /// 既存の実行記録を更新する（実行完了時）。
    func update(_ record: ExecutionRecord) {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        guard var records = cache[record.taskId] else { return }
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
            cache[record.taskId] = records
            saveTaskLog(taskId: record.taskId, records: records)
        }
    }

    // MARK: - 読み取り

    /// 指定タスクの実行履歴を取得する。
    func history(taskId: String, limit: Int = 50) -> [ExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        let records = cache[taskId] ?? []
        return Array(records.suffix(limit))
    }

    /// 全タスクの実行履歴をタイムライン順（新しい順）で取得する。
    func timeline(limit: Int = 100) -> [ExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        let all = cache.values.flatMap { $0 }
        return Array(all.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    /// 指定タスクの最新の実行記録を取得する。
    func lastRecord(taskId: String) -> ExecutionRecord? {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        return cache[taskId]?.last
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }

        let decoder = JSONDecoder()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = isoFormatter.date(from: str) { return date }
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }

        for file in files where file.pathExtension == "json" {
            let taskId = file.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: file),
                  let records = try? decoder.decode([ExecutionRecord].self, from: data) else { continue }
            cache[taskId] = records
        }
    }

    private func saveTaskLog(taskId: String, records: [ExecutionRecord]) {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // 最大500件に絞る
        let trimmed = Array(records.suffix(500))

        guard let data = try? encoder.encode(trimmed) else { return }
        let url = directory.appendingPathComponent("\(taskId).json")
        try? data.write(to: url, options: .atomic)
    }
}
