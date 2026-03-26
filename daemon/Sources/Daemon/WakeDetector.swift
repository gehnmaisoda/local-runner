import Foundation
import AppKit
import Core

/// macOS のスリープ/復帰イベントを監視し、復帰時にコールバックを呼ぶ。
/// sleepStartedAt をファイルに永続化し、デーモン再起動時にも復元可能にする。
/// また heartbeat を定期的に記録し、起動時にギャップを検出してキャッチアップの判断材料にする。
final class WakeDetector: @unchecked Sendable {
    private let onWake: @Sendable (Date) -> Void
    private var sleepStartedAt: Date?
    private var heartbeatTimer: Timer?

    /// Heartbeat の記録間隔（秒）。
    private static let heartbeatInterval: TimeInterval = 60

    init(onWake: @escaping @Sendable (Date) -> Void) {
        self.onWake = onWake
    }

    func start() {
        // 永続化されたスリープ状態を復元
        sleepStartedAt = loadSleepState()
        if let restored = sleepStartedAt {
            print("[WakeDetector] 前回のスリープ状態を復元: \(restored)")
        }

        // スリープ/復帰イベントの監視
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            let now = Date()
            self?.sleepStartedAt = now
            self?.saveSleepState(now)
            print("[WakeDetector] システムがスリープに入ります")
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let sleepDate = self.sleepStartedAt else { return }
            self.sleepStartedAt = nil
            self.clearSleepState()
            print("[WakeDetector] システムが復帰しました (\(sleepDate) からスリープ)")
            self.onWake(sleepDate)
        }

        // Heartbeat の定期記録
        writeHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.writeHeartbeat()
        }
    }

    // MARK: - 起動時ギャップ検出

    /// 前回の heartbeat からのギャップを検出する。
    /// デーモンが停止していた期間にスケジュールを逃した可能性がある場合、その開始時刻を返す。
    func detectStartupGap() -> Date? {
        // 永続化されたスリープ状態があれば、それを使う（デーモン再起動ケース）
        if let sleepDate = loadSleepState() {
            clearSleepState()
            sleepStartedAt = nil
            return sleepDate
        }

        // Heartbeat ファイルが存在すれば、最後の heartbeat 時刻を取得
        let file = ConfigPaths.heartbeatFile
        guard let data = try? Data(contentsOf: file),
              let str = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(str) else {
            return nil
        }

        let lastHeartbeat = Date(timeIntervalSince1970: timestamp)
        let gap = Date().timeIntervalSince(lastHeartbeat)

        // Heartbeat 間隔の3倍以上のギャップがあれば、デーモンが停止していたと判断
        if gap > Self.heartbeatInterval * 3 {
            print("[WakeDetector] 起動時ギャップを検出: 最終 heartbeat \(lastHeartbeat) (約\(Int(gap))秒前)")
            return lastHeartbeat
        }

        return nil
    }

    // MARK: - 永続化

    private func saveSleepState(_ date: Date) {
        let str = String(date.timeIntervalSince1970)
        try? str.write(to: ConfigPaths.sleepStateFile, atomically: true, encoding: .utf8)
    }

    private func loadSleepState() -> Date? {
        guard let data = try? Data(contentsOf: ConfigPaths.sleepStateFile),
              let str = String(data: data, encoding: .utf8),
              let timestamp = TimeInterval(str) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func clearSleepState() {
        try? FileManager.default.removeItem(at: ConfigPaths.sleepStateFile)
    }

    private func writeHeartbeat() {
        let str = String(Date().timeIntervalSince1970)
        try? str.write(to: ConfigPaths.heartbeatFile, atomically: true, encoding: .utf8)
    }
}
