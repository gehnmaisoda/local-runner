import Foundation
import IOKit.pwr_mgt
import CoreGraphics

/// DarkWake（ディスプレイ消灯中の短時間復帰）を検知し、タスク実行可否を判定する。
///
/// - ディスプレイ ON → 実行可
/// - ディスプレイ OFF + Sleep防止 Assertion あり（Amphetamine等）→ 実行可
/// - ディスプレイ OFF + Assertion なし → DarkWake、スキップ
protocol DisplayWakeStateChecking: Sendable {
    func shouldExecuteScheduledTasks() -> Bool
}

final class DisplayWakeState: DisplayWakeStateChecking, @unchecked Sendable {
    func shouldExecuteScheduledTasks() -> Bool {
        let displayID = CGMainDisplayID()
        guard displayID != kCGNullDirectDisplay else {
            // ディスプレイ状態を取得できない場合は安全側（実行する）
            return true
        }

        if CGDisplayIsAsleep(displayID) == 0 {
            return true
        }

        // ディスプレイ消灯中: Sleep防止 Assertion があれば実行を許可
        return hasSleepPreventionAssertions()
    }

    private func hasSleepPreventionAssertions() -> Bool {
        var assertionsStatus: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsStatus(&assertionsStatus)
        guard result == kIOReturnSuccess,
              let cfDict = assertionsStatus?.takeRetainedValue() else {
            return true
        }

        let dict = cfDict as NSDictionary
        let relevantKeys = [
            "PreventUserIdleSystemSleep",
            "PreventUserIdleDisplaySleep",
            "PreventSystemSleep",
        ]

        for key in relevantKeys {
            if let value = dict[key] as? Int, value > 0 {
                return true
            }
        }

        return false
    }
}
