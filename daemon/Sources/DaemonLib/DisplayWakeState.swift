import Foundation
import IOKit.pwr_mgt
import CoreGraphics

/// DarkWake（ディスプレイ消灯中の短時間復帰）を検知し、タスク実行可否を判定する。
///
/// - ディスプレイ ON → 実行可
/// - ディスプレイ OFF + Sleep防止 Assertion あり（Amphetamine等）→ 実行可
/// - ディスプレイ OFF + Assertion なし → DarkWake、スキップ
public protocol DisplayWakeStateChecking: Sendable {
    func shouldExecuteScheduledTasks() -> Bool
}

public final class DisplayWakeState: DisplayWakeStateChecking, @unchecked Sendable {
    public func shouldExecuteScheduledTasks() -> Bool {
        let displayID = CGMainDisplayID()
        guard displayID != kCGNullDirectDisplay else {
            // ディスプレイ状態を取得できない場合は安全側（実行しない）
            // DarkWake 中は GPU 未初期化で kCGNullDirectDisplay が返る
            Log.info("DisplayWakeState", "ディスプレイID取得不可 — DarkWake の可能性があるためスキップ")
            return false
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
            Log.info("DisplayWakeState", "Assertion 状態を取得できないためスキップ")
            return false
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
