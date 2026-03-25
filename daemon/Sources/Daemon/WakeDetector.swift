import Foundation
import AppKit

/// macOS のスリープ/復帰イベントを監視し、復帰時にコールバックを呼ぶ。
final class WakeDetector: @unchecked Sendable {
    private let onWake: @Sendable (Date) -> Void
    /// スリープ開始時刻を記録する。
    private var sleepStartedAt: Date?

    init(onWake: @escaping @Sendable (Date) -> Void) {
        self.onWake = onWake
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sleepStartedAt = Date()
            print("[WakeDetector] System going to sleep")
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let sleepDate = self.sleepStartedAt else { return }
            self.sleepStartedAt = nil
            print("[WakeDetector] System woke up (slept since \(sleepDate))")
            self.onWake(sleepDate)
        }
    }
}
