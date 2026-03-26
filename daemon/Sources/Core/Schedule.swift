import Foundation

/// スケジュール種別。
public enum ScheduleType: String, Codable, Sendable, CaseIterable {
    case everyMinute = "every_minute"
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case cron = "cron"
}

/// タスクの実行スケジュール定義。
public struct Schedule: Codable, Sendable, Equatable {
    public var type: ScheduleType
    public var minute: Int?        // hourly: 何分に実行 (0-59)
    public var time: String?       // daily/weekly/monthly: "HH:mm"
    public var weekday: Int?       // weekly (レガシー単体): 1=月...7=日
    public var weekdays: [Int]?    // weekly (マルチセレクト): [1,3,5] = 月水金
    public var monthDays: [Int]?   // monthly: 日付リスト (-1 = 月末)
    public var expression: String? // cron: cron式

    enum CodingKeys: String, CodingKey {
        case type, minute, time, weekday, weekdays, expression
        case monthDays = "month_days"
    }

    public init(
        type: ScheduleType,
        minute: Int? = nil,
        time: String? = nil,
        weekday: Int? = nil,
        weekdays: [Int]? = nil,
        monthDays: [Int]? = nil,
        expression: String? = nil
    ) {
        self.type = type
        self.minute = minute
        self.time = time
        self.weekday = weekday
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.expression = expression
    }

    // MARK: - コンビニエンス

    public static var everyMinute: Schedule { .init(type: .everyMinute) }
    public static func hourly(minute: Int = 0) -> Schedule { .init(type: .hourly, minute: minute) }
    public static func daily(time: String = "00:00") -> Schedule { .init(type: .daily, time: time) }
    public static func weekly(weekday: Int = 1, time: String = "00:00") -> Schedule {
        .init(type: .weekly, time: time, weekday: weekday)
    }
    public static func weekly(weekdays: [Int], time: String = "00:00") -> Schedule {
        .init(type: .weekly, time: time, weekdays: weekdays)
    }
    public static func monthly(days: [Int] = [1], time: String = "00:00") -> Schedule {
        .init(type: .monthly, time: time, monthDays: days)
    }
    public static func cron(_ expression: String) -> Schedule { .init(type: .cron, expression: expression) }

    // MARK: - 表示

    /// 有効な曜日リストを返す。weekdays が優先、なければ weekday を使用。
    private var effectiveWeekdays: [Int] {
        if let wds = weekdays, !wds.isEmpty { return wds.sorted() }
        return [weekday ?? 1]
    }

    public var displayText: String {
        switch type {
        case .everyMinute: return "毎分"
        case .hourly: return "毎時 \(minute ?? 0)分"
        case .daily: return "毎日 \(time ?? "00:00")"
        case .weekly:
            let dayNames = effectiveWeekdays.map { weekdayName($0) }
            return "毎週\(dayNames.joined()) \(time ?? "00:00")"
        case .monthly:
            let days = monthDays ?? [1]
            let dayStrs = days.sorted().map { $0 == -1 ? "月末" : "\($0)日" }
            return "毎月\(dayStrs.joined(separator: "・")) \(time ?? "00:00")"
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
            let targets = effectiveWeekdays.map { isoWeekdayToCalendarWeekday($0) }
            var comps = cal.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = min
            comps.second = 0
            guard var next = cal.date(from: comps) else { return nil }
            for _ in 0..<8 {
                if targets.contains(cal.component(.weekday, from: next)) && next > date {
                    return next
                }
                guard let advanced = cal.date(byAdding: .day, value: 1, to: next) else { return nil }
                next = advanced
            }
            return nil

        case .monthly:
            let (hour, min) = parseTime(time ?? "00:00")
            let days = monthDays ?? [1]

            var candidates: [Date] = []

            for monthOffset in 0...1 {
                guard let baseMonth = cal.date(byAdding: .month, value: monthOffset, to: date) else { continue }

                for day in days {
                    var comps = cal.dateComponents([.year, .month], from: baseMonth)
                    if day == -1 {
                        // 月末
                        guard let range = cal.range(of: .day, in: .month, for: baseMonth) else { continue }
                        comps.day = range.count
                    } else {
                        comps.day = day
                    }
                    comps.hour = hour
                    comps.minute = min
                    comps.second = 0

                    guard let candidate = cal.date(from: comps) else { continue }
                    // 無効な日付（2/30 等）は月がずれるので除外
                    if cal.component(.month, from: candidate) == cal.component(.month, from: baseMonth)
                        && candidate > date {
                        candidates.append(candidate)
                    }
                }
            }

            return candidates.min()

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
        case 1: return "月"
        case 2: return "火"
        case 3: return "水"
        case 4: return "木"
        case 5: return "金"
        case 6: return "土"
        case 7: return "日"
        default: return "月"
        }
    }
}
