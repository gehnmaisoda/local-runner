import Foundation
import IOKit

/// DarkWake（ディスプレイ消灯中の短時間復帰）を検知し、タスク実行可否を判定する。
///
/// IOKit の IOPMrootDomain から "System Capabilities" を読み取り、
/// Graphics ビット (0x02) の有無で Full Wake / DarkWake を判定する。
/// CG Display API (CGDisplayIsAsleep) は DarkWake 中の挙動が不安定なため使用しない。
///
/// - Full Wake (caps & 0x02 != 0) → 実行可
/// - DarkWake  (caps & 0x02 == 0) → スキップ
public protocol DisplayWakeStateChecking: Sendable {
    func shouldExecuteScheduledTasks() -> Bool
}

public final class DisplayWakeState: DisplayWakeStateChecking, @unchecked Sendable {
    /// kIOPMSystemCapabilityGraphics (xnu: IOPM.h)
    static let graphicsBit: Int = 0x02

    public init() {}

    /// System Capabilities の値から Full Wake かどうかを判定する純粋関数。
    static func isFullWake(capabilities: Int) -> Bool {
        (capabilities & graphicsBit) != 0
    }

    public func shouldExecuteScheduledTasks() -> Bool {
        guard let caps = Self.readSystemCapabilities() else {
            Log.info("DisplayWakeState", "System Capabilities を取得できないためスキップ")
            return false
        }

        let result = Self.isFullWake(capabilities: caps)

        if !result {
            Log.info("DisplayWakeState", "Graphics capability なし (caps=\(caps)) — DarkWake のためスキップ")
        }

        return result
    }

    /// IOPMrootDomain から "System Capabilities" を読み取る。
    private static func readSystemCapabilities() -> Int? {
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        guard let capsCF = IORegistryEntryCreateCFProperty(entry, "System Capabilities" as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        // CFNumber は環境によって Int32/Int64 で格納されうるため NSNumber 経由で安全に取得
        return (capsCF.takeRetainedValue() as? NSNumber)?.intValue
    }
}
