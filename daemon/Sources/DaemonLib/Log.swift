import Foundation

/// システムタイムゾーンの ISO 8601 タイムスタンプ付きログ出力。
public enum Log {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f
    }()

    public static func info(_ tag: String, _ message: String) {
        print("[\(formatter.string(from: Date()))] [\(tag)] \(message)")
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
