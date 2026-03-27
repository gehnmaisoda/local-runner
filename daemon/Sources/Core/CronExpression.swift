import Foundation

/// cron 式パースエラー。
public enum CronError: Error, Sendable {
    case invalidFormat
    case invalidField(String)
}

/// cron 式の1フィールド。
public enum CronField: Sendable, Equatable {
    case any
    case values(Set<Int>)

    public func matches(_ value: Int) -> Bool {
        switch self {
        case .any: return true
        case .values(let set): return set.contains(value)
        }
    }

    /// フィールド文字列をパースする。
    public static func parse(_ field: String, range: ClosedRange<Int>) throws -> CronField {
        let field = field.trimmingCharacters(in: .whitespaces)
        if field == "*" { return .any }

        var values = Set<Int>()
        let parts = field.split(separator: ",")
        for part in parts {
            let s = String(part)
            if s.contains("/") {
                let stepParts = s.split(separator: "/")
                guard stepParts.count == 2, let step = Int(stepParts[1]), step > 0 else {
                    throw CronError.invalidField(field)
                }
                let baseRange: ClosedRange<Int>
                if stepParts[0] == "*" {
                    baseRange = range
                } else if stepParts[0].contains("-") {
                    let rParts = stepParts[0].split(separator: "-")
                    guard rParts.count == 2, let lo = Int(rParts[0]), let hi = Int(rParts[1]) else {
                        throw CronError.invalidField(field)
                    }
                    baseRange = lo...hi
                } else {
                    guard let start = Int(stepParts[0]) else {
                        throw CronError.invalidField(field)
                    }
                    baseRange = start...range.upperBound
                }
                for v in stride(from: baseRange.lowerBound, through: baseRange.upperBound, by: step) {
                    values.insert(v)
                }
            } else if s.contains("-") {
                let rParts = s.split(separator: "-")
                guard rParts.count == 2, let lo = Int(rParts[0]), let hi = Int(rParts[1]) else {
                    throw CronError.invalidField(field)
                }
                for v in lo...hi { values.insert(v) }
            } else {
                guard let v = Int(s) else {
                    throw CronError.invalidField(field)
                }
                values.insert(v)
            }
        }
        return .values(values)
    }
}

/// 5フィールドの cron 式をパースし、次回実行日時を計算する。
/// フォーマット: "分 時 日 月 曜日"
public struct CronExpression: Sendable {
    public let minute: CronField
    public let hour: CronField
    public let dayOfMonth: CronField
    public let month: CronField
    public let dayOfWeek: CronField
    public let raw: String

    public init(_ expression: String) throws {
        self.raw = expression
        let parts = expression.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 5 else {
            throw CronError.invalidFormat
        }
        minute = try CronField.parse(String(parts[0]), range: 0...59)
        hour = try CronField.parse(String(parts[1]), range: 0...23)
        dayOfMonth = try CronField.parse(String(parts[2]), range: 1...31)
        month = try CronField.parse(String(parts[3]), range: 1...12)
        // 0 と 7 はどちらも日曜。7 が指定されたら 0 も含める正規化を行う
        var dow = try CronField.parse(String(parts[4]), range: 0...7)
        if case .values(var set) = dow, set.contains(7) {
            set.insert(0)
            dow = .values(set)
        }
        dayOfWeek = dow
    }

    /// cron 式が有効かどうかを検証する。
    public static func validate(_ expression: String) -> Bool {
        (try? CronExpression(expression)) != nil
    }

    /// 指定日時以降の次回実行日時を返す。最大4年先まで探索する。
    public func nextDate(after date: Date) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        comps.second = 0
        guard var candidate = cal.date(from: comps) else { return nil }
        guard let nextMin = cal.date(byAdding: .minute, value: 1, to: candidate) else { return nil }
        candidate = nextMin

        guard let maxDate = cal.date(byAdding: .year, value: 4, to: date) else { return nil }

        while candidate < maxDate {
            let c = cal.dateComponents([.minute, .hour, .day, .month, .weekday], from: candidate)
            guard let m = c.minute, let h = c.hour, let d = c.day,
                  let mo = c.month, let wd = c.weekday else {
                return nil
            }

            // 月チェック
            if !month.matches(mo) {
                guard let next = advanceMonth(candidate, cal: cal) else { return nil }
                candidate = next
                continue
            }

            // 日チェック (day-of-month AND day-of-week)
            let cronWeekday = wd - 1 // Calendar(1=日) → cron(0=日)
            if !dayOfMonth.matches(d) || !dayOfWeek.matches(cronWeekday) {
                let startOfDay = cal.startOfDay(for: candidate)
                guard let next = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
                candidate = next
                continue
            }

            // 時チェック
            if !hour.matches(h) {
                guard let next = cal.date(byAdding: .hour, value: 1, to: candidate) else { return nil }
                var nc = cal.dateComponents([.year, .month, .day, .hour], from: next)
                nc.minute = 0
                nc.second = 0
                candidate = cal.date(from: nc) ?? next
                continue
            }

            // 分チェック
            if !minute.matches(m) {
                guard let next = cal.date(byAdding: .minute, value: 1, to: candidate) else { return nil }
                candidate = next
                continue
            }

            return candidate
        }

        return nil
    }

    // MARK: - Private

    private func advanceMonth(_ date: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month], from: date)
        comps.day = 1
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let firstOfMonth = cal.date(from: comps) else { return nil }
        return cal.date(byAdding: .month, value: 1, to: firstOfMonth)
    }
}
