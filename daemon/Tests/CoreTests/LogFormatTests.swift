import Testing
import Foundation

/// Log.formatDuration (Daemon ターゲット) のロジック検証。
/// Daemon は executableTarget のため CoreTests から直接 import できない。
/// ロジックをミラーしてアルゴリズムの正しさを担保する。
/// Log.formatDuration を変更した場合はこのテストも同期すること。
private func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    if total < 60 { return "\(total)秒" }
    if total < 3600 { return "\(total / 60)分\(total % 60)秒" }
    return "\(total / 3600)時間\((total % 3600) / 60)分"
}

@Suite("Log.formatDuration logic")
struct FormatDurationTests {
    @Test("Under 60 seconds shows seconds")
    func seconds() {
        #expect(formatDuration(0) == "0秒")
        #expect(formatDuration(1) == "1秒")
        #expect(formatDuration(59) == "59秒")
    }

    @Test("Boundary at 60 seconds switches to minutes")
    func minutesBoundary() {
        #expect(formatDuration(60) == "1分0秒")
    }

    @Test("Minutes and seconds")
    func minutesAndSeconds() {
        #expect(formatDuration(90) == "1分30秒")
        #expect(formatDuration(3599) == "59分59秒")
    }

    @Test("Boundary at 3600 seconds switches to hours")
    func hoursBoundary() {
        #expect(formatDuration(3600) == "1時間0分")
    }

    @Test("Hours and minutes")
    func hoursAndMinutes() {
        #expect(formatDuration(3661) == "1時間1分")
        #expect(formatDuration(7200) == "2時間0分")
    }

    @Test("Fractional seconds are truncated to integer")
    func fractional() {
        #expect(formatDuration(59.9) == "59秒")
        #expect(formatDuration(0.5) == "0秒")
    }
}
