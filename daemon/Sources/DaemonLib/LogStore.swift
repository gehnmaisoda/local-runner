import Foundation
import Core

/// 実行ログの永続化とクエリを担当する。
/// ログは ~/Library/Application Support/LocalRunner/logs/ にタスクIDごとの JSON ファイルとして保存される。
public final class LogStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    /// タスクID → 実行履歴（メモリキャッシュ）
    private var cache: [String: [ExecutionRecord]] = [:]
    private var loaded = false

    public init(directory: URL = ConfigPaths.logsDirectory) {
        self.directory = directory
    }

    // MARK: - 書き込み

    /// 実行記録を追加する。
    public func append(_ record: ExecutionRecord) {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        var records = cache[record.taskId] ?? []
        records.append(record)
        cache[record.taskId] = records
        saveTaskLog(taskId: record.taskId, records: records)
    }

    /// 既存の実行記録を更新する（実行完了時）。
    public func update(_ record: ExecutionRecord) {
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

    /// 指定タスクの実行ログを全削除する。
    public func deleteHistory(taskId: String) {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        cache.removeValue(forKey: taskId)
        let url = directory.appendingPathComponent("\(taskId).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// 起動時に孤立した "running" / "pending" レコードを "stopped" に更新する。
    /// 前回の daemon 停止時に完了できなかった実行・保留中タスクの後始末。
    public func cleanupOrphanedRecords() {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        let orphanStatuses: Set<ExecutionStatus> = [.running, .pending]
        var changed = false
        for (taskId, records) in cache {
            let updated = records.map { record -> ExecutionRecord in
                guard orphanStatuses.contains(record.status) else { return record }
                changed = true
                return ExecutionRecord(
                    id: record.id,
                    taskId: record.taskId,
                    taskName: record.taskName,
                    command: record.command,
                    workingDirectory: record.workingDirectory,
                    startedAt: record.startedAt,
                    finishedAt: record.finishedAt ?? record.startedAt,
                    exitCode: nil,
                    stdout: record.stdout,
                    stderr: record.stderr,
                    status: .stopped
                )
            }
            if updated != records {
                cache[taskId] = updated
                saveTaskLog(taskId: taskId, records: updated)
            }
        }
        if changed {
            Log.info("LogStore", "孤立したレコードを停止に更新しました")
        }
    }

    // MARK: - 読み取り

    /// 指定タスクの実行履歴を取得する。
    public func history(taskId: String, limit: Int = 50) -> [ExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        let records = cache[taskId] ?? []
        return Array(records.suffix(limit))
    }

    /// 全タスクの実行履歴をタイムライン順（新しい順）で取得する。
    public func timeline(limit: Int = 100) -> [ExecutionRecord] {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        let all = cache.values.flatMap { $0 }
        return Array(all.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    /// 指定タスクの最新の実行記録を取得する。
    public func lastRecord(taskId: String) -> ExecutionRecord? {
        lock.lock()
        defer { lock.unlock() }

        ensureLoaded()
        return cache[taskId]?.last
    }

    // MARK: - Private

    private func ensureLoaded() {
        guard !loaded else { return }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            loaded = true
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: str) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }

        for file in files where file.pathExtension == "json" {
            let taskId = file.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: file),
                  let records = try? decoder.decode([ExecutionRecord].self, from: data) else { continue }
            cache[taskId] = records
        }

        loaded = true
    }

    private func saveTaskLog(taskId: String, records: [ExecutionRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(fmt.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // 最大500件に絞る
        let trimmed = Array(records.suffix(500))

        guard let data = try? encoder.encode(trimmed) else { return }
        let url = directory.appendingPathComponent("\(taskId).json")
        try? data.write(to: url, options: .atomic)
    }
}
