import Foundation

/// スケジュール種別。
public enum ScheduleType: String, Codable, Sendable, CaseIterable {
    case everyMinute = "every_minute"
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case cron = "cron"
}

/// タスクの実行スケジュール定義。
public struct Schedule: Codable, Sendable, Equatable {
    public var type: ScheduleType
    public var minute: Int?       // hourly: 何分に実行 (0-59)
    public var time: String?      // daily/weekly: "HH:mm"
    public var weekday: Int?      // weekly: 1=月...7=日
    public var expression: String? // cron: cron式

    public init(
        type: ScheduleType,
        minute: Int? = nil,
        time: String? = nil,
        weekday: Int? = nil,
        expression: String? = nil
    ) {
        self.type = type
        self.minute = minute
        self.time = time
        self.weekday = weekday
        self.expression = expression
    }

    // MARK: - コンビニエンス

    public static var everyMinute: Schedule { .init(type: .everyMinute) }
    public static func hourly(minute: Int = 0) -> Schedule { .init(type: .hourly, minute: minute) }
    public static func daily(time: String = "00:00") -> Schedule { .init(type: .daily, time: time) }
    public static func weekly(weekday: Int = 1, time: String = "00:00") -> Schedule {
        .init(type: .weekly, time: time, weekday: weekday)
    }
    public static func cron(_ expression: String) -> Schedule { .init(type: .cron, expression: expression) }

    // MARK: - 表示

    public var displayText: String {
        switch type {
        case .everyMinute: return "毎分"
        case .hourly: return "毎時 \(minute ?? 0)分"
        case .daily: return "毎日 \(time ?? "00:00")"
        case .weekly:
            return "毎週\(weekdayName(weekday ?? 1)) \(time ?? "00:00")"
        case .cron: return expression ?? ""
        }
    }

    // MARK: - 次回実行日時

    /// 指定日時以降の次回実行日時を計算する。
    public func nextFireDate(after date: Date) -> Date? {
        let cal = Calendar.current

        switch type {
        case .everyMinute:
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard let truncated = cal.date(from: comps) else { return nil }
            return cal.date(byAdding: .minute, value: 1, to: truncated)

        case .hourly:
            let m = minute ?? 0
            // 現在の時間で指定分を設定
            var comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
            comps.minute = m
            comps.second = 0
            guard var next = cal.date(from: comps) else { return nil }
            if next <= date {
                next = cal.date(byAdding: .hour, value: 1, to: next) ?? next
            }
            return next

        case .daily:
            let (hour, min) = parseTime(time ?? "00:00")
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = min
            comps.second = 0
            guard var next = cal.date(from: comps) else { return nil }
            if next <= date {
                next = cal.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next

        case .weekly:
            let (hour, min) = parseTime(time ?? "00:00")
            let targetWeekday = isoWeekdayToCalendarWeekday(weekday ?? 1)
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = min
            comps.second = 0
            guard var next = cal.date(from: comps) else { return nil }
            while cal.component(.weekday, from: next) != targetWeekday || next <= date {
                guard let advanced = cal.date(byAdding: .day, value: 1, to: next) else { return nil }
                next = advanced
            }
            return next

        case .cron:
            guard let expr = expression, let cron = try? CronExpression(expr) else { return nil }
            return cron.nextDate(after: date)
        }
    }

    // MARK: - Private

    private func parseTime(_ time: String) -> (hour: Int, minute: Int) {
        let parts = time.split(separator: ":")
        let hour = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (hour, minute)
    }

    /// ISO weekday (1=月曜) → Calendar weekday (1=日曜, 2=月曜, ...)
    private func isoWeekdayToCalendarWeekday(_ iso: Int) -> Int {
        iso == 7 ? 1 : iso + 1
    }

    private func weekdayName(_ day: Int) -> String {
        switch day {
        case 1: return "月曜"
        case 2: return "火曜"
        case 3: return "水曜"
        case 4: return "木曜"
        case 5: return "金曜"
        case 6: return "土曜"
        case 7: return "日曜"
        default: return "月曜"
        }
    }
}
