import Foundation
import Core

/// システムタイムゾーンの ISO 8601 タイムスタンプ付きログ出力。
public enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f
    }()

    private static let bufferLock = NSLock()
    nonisolated(unsafe) private static var buffer: [LogEntry] = []
    private static let maxEntries = 1000

    public static func info(_ tag: String, _ message: String) {
        let now = Date()
        print("[\(formatter.string(from: now))] [\(tag)] \(message)")

        let entry = LogEntry(timestamp: now, tag: tag, message: message)
        bufferLock.lock()
        buffer.append(entry)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        bufferLock.unlock()
    }

    /// バッファ内のログエントリを返す。
    public static func entries(limit: Int = 1000) -> [LogEntry] {
        bufferLock.lock()
        let result = Array(buffer.suffix(limit))
        bufferLock.unlock()
        return result
    }

    /// バッファをクリアする。
    public static func clear() {
        bufferLock.lock()
        buffer.removeAll()
        bufferLock.unlock()
    }

    /// Date を ISO 8601 形式 (例: 2026-03-30T17:09:03+09:00) で返す。
    public static func formatDate(_ date: Date) -> String {
        formatter.string(from: date)
    }

    /// TimeInterval を読みやすいテキストに変換する。
    public static func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        if total < 60 { return "\(total)秒" }
        if total < 3600 { return "\(total / 60)分\(total % 60)秒" }
        return "\(total / 3600)時間\((total % 3600) / 60)分"
    }
}
