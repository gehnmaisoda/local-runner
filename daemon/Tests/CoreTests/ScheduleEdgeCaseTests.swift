import Testing
import Foundation
@testable import Core

// MARK: - Helper

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    return Calendar.current.date(from: comps)!
}

private let cal = Calendar.current

// MARK: - Weekly schedule

@Suite("Schedule.nextFireDate - weekly")
struct WeeklyScheduleTests {
    @Test("Single weekday: next Monday from a Thursday")
    func singleWeekday() {
        // 2026-03-26 is Thursday. ISO weekday 1 = Monday → next Monday is 2026-03-30
        let schedule = Schedule.weekly(weekday: 1, time: "09:00")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next!)
        #expect(comps.month == 3)
        #expect(comps.day == 30)
        #expect(comps.hour == 9)
        #expect(comps.minute == 0)
    }

    @Test("Single weekday: same day before scheduled time fires today")
    func sameDay() {
        // 2026-03-26 is Thursday (ISO weekday 4). Schedule for Thursday 15:00, from 10:00
        let schedule = Schedule.weekly(weekday: 4, time: "15:00")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 26)
        #expect(cal.component(.hour, from: next!) == 15)
    }

    @Test("Multiple weekdays: picks nearest matching day")
    func multipleWeekdays() {
        // 2026-03-26 is Thursday. weekdays=[1,5] (Mon, Fri) → next is Friday 2026-03-27
        let schedule = Schedule.weekly(weekdays: [1, 5], time: "09:00")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 27)
    }

    @Test("Weekdays=[7] (Sunday) resolves correctly")
    func sunday() {
        // 2026-03-26 is Thursday. Sunday ISO=7 → next Sunday is 2026-03-29
        let schedule = Schedule.weekly(weekdays: [7], time: "10:00")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 29)
    }

    @Test("Empty weekdays array falls back to weekday field")
    func emptyWeekdaysArray() {
        // weekdays is empty, weekday defaults to 1 (Monday)
        let schedule = Schedule(type: .weekly, time: "09:00", weekdays: [])
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        // Should fall back to weekday=1 (Monday) → 2026-03-30
        #expect(cal.component(.day, from: next!) == 30)
    }

    @Test("Out-of-range weekday values are filtered")
    func outOfRangeWeekdays() {
        // effectiveWeekdays filters to 1-7. weekdays=[0, 8, 3] → only 3 (Wednesday) is valid
        let schedule = Schedule(type: .weekly, time: "09:00", weekdays: [0, 8, 3])
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        // Wednesday = 2026-04-01
        #expect(cal.component(.month, from: next!) == 4)
        #expect(cal.component(.day, from: next!) == 1)
    }

    @Test("Wraps across month boundary")
    func monthBoundary() {
        // 2026-03-30 Monday. weekday=6 (Saturday) → 2026-04-04
        let schedule = Schedule.weekly(weekday: 6, time: "12:00")
        let from = date(2026, 3, 30, 13, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.month, from: next!) == 4)
        #expect(cal.component(.day, from: next!) == 4)
    }
}

// MARK: - Monthly schedule

@Suite("Schedule.nextFireDate - monthly")
struct MonthlyScheduleTests {
    @Test("Month-end (-1) in March gives 31st")
    func monthEndMarch() {
        let schedule = Schedule.monthly(days: [-1], time: "09:00")
        let from = date(2026, 3, 15, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 31)
        #expect(cal.component(.month, from: next!) == 3)
    }

    @Test("Month-end (-1) in April gives 30th")
    func monthEndApril() {
        let schedule = Schedule.monthly(days: [-1], time: "09:00")
        let from = date(2026, 4, 1, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 30)
        #expect(cal.component(.month, from: next!) == 4)
    }

    @Test("Month-end (-1) in February non-leap gives 28th")
    func monthEndFeb() {
        // 2026 is not a leap year
        let schedule = Schedule.monthly(days: [-1], time: "09:00")
        let from = date(2026, 2, 1, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 28)
        #expect(cal.component(.month, from: next!) == 2)
    }

    @Test("Month-end (-1) in February leap year gives 29th")
    func monthEndFebLeap() {
        // 2028 is a leap year
        let schedule = Schedule.monthly(days: [-1], time: "09:00")
        let from = date(2028, 2, 1, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 29)
    }

    @Test("Day 31 in 30-day month skips to next month")
    func day31InApril() {
        // April has 30 days. day=31 in April should skip to May 31
        let schedule = Schedule.monthly(days: [31], time: "09:00")
        let from = date(2026, 4, 1, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.month, from: next!) == 5)
        #expect(cal.component(.day, from: next!) == 31)
    }

    @Test("Day 30 in February skips to March")
    func day30InFeb() {
        let schedule = Schedule.monthly(days: [30], time: "09:00")
        let from = date(2026, 2, 1, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.month, from: next!) == 3)
        #expect(cal.component(.day, from: next!) == 30)
    }

    @Test("Multiple days picks earliest future one")
    func multipleDays() {
        // days=[5, 20], from March 10 → March 20
        let schedule = Schedule.monthly(days: [5, 20], time: "09:00")
        let from = date(2026, 3, 10, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 20)
        #expect(cal.component(.month, from: next!) == 3)
    }

    @Test("Multiple days wraps to next month if all past")
    func multipleDaysNextMonth() {
        // days=[1, 5], from March 10 → April 1
        let schedule = Schedule.monthly(days: [1, 5], time: "09:00")
        let from = date(2026, 3, 10, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 1)
        #expect(cal.component(.month, from: next!) == 4)
    }

    @Test("Mixed -1 and specific day picks earliest")
    func monthEndAndSpecificDay() {
        // days=[15, -1], from March 10 → March 15 (before month-end)
        let schedule = Schedule.monthly(days: [15, -1], time: "09:00")
        let from = date(2026, 3, 10, 0, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 15)
    }
}

// MARK: - parseTime via schedule behavior

@Suite("Schedule time parsing edge cases")
struct ParseTimeTests {
    @Test("Malformed time 25:00 returns nil (invalid hour)")
    func invalidHour() {
        let schedule = Schedule.daily(time: "25:00")
        let from = date(2026, 3, 26, 10, 0)
        // parseTime now validates: hour 25 is out of range → returns nil
        #expect(schedule.nextFireDate(after: from) == nil)
    }

    @Test("Missing colon defaults to hour only")
    func missingColon() {
        // "09" → parts=["09"], minute defaults to 0
        let schedule = Schedule.daily(time: "09")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        // Should resolve to 09:00 next day
        #expect(cal.component(.hour, from: next!) == 9)
        #expect(cal.component(.minute, from: next!) == 0)
    }

    @Test("Empty time string defaults to 00:00")
    func emptyTime() {
        let schedule = Schedule.daily(time: "")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.hour, from: next!) == 0)
        #expect(cal.component(.minute, from: next!) == 0)
    }

    @Test("Non-numeric time defaults to 0:0 which is valid")
    func nonNumericTime() {
        let schedule = Schedule.daily(time: "abc:def")
        let from = date(2026, 3, 26, 10, 0)
        let next = schedule.nextFireDate(after: from)
        // Int("abc") → nil → 0, Int("def") → nil → 0 → (0, 0) is valid
        #expect(next != nil)
        #expect(cal.component(.hour, from: next!) == 0)
        #expect(cal.component(.minute, from: next!) == 0)
    }
}

// MARK: - parseTime validation

@Suite("Schedule.parseTime validation")
struct ParseTimeValidationTests {

    @Test("Valid time 00:00 returns (0, 0)")
    func validMidnight() {
        let result = Schedule.parseTime("00:00")
        #expect(result != nil)
        #expect(result?.hour == 0)
        #expect(result?.minute == 0)
    }

    @Test("Valid time 23:59 returns (23, 59)")
    func validMaxTime() {
        let result = Schedule.parseTime("23:59")
        #expect(result != nil)
        #expect(result?.hour == 23)
        #expect(result?.minute == 59)
    }

    @Test("Valid time 12:30 returns (12, 30)")
    func validNoonish() {
        let result = Schedule.parseTime("12:30")
        #expect(result != nil)
        #expect(result?.hour == 12)
        #expect(result?.minute == 30)
    }

    @Test("Invalid time 25:99 returns nil")
    func invalidTime2599() {
        let result = Schedule.parseTime("25:99")
        #expect(result == nil)
    }

    @Test("Invalid time 24:00 returns nil (hour out of range)")
    func invalidTime2400() {
        let result = Schedule.parseTime("24:00")
        #expect(result == nil)
    }

    @Test("Invalid time 00:60 returns nil (minute out of range)")
    func invalidTime0060() {
        let result = Schedule.parseTime("00:60")
        #expect(result == nil)
    }

    @Test("Invalid time -1:00 returns nil")
    func invalidNegativeHour() {
        // "-1" is parsed by Int() but -1 is out of 0-23 range
        let result = Schedule.parseTime("-1:00")
        #expect(result == nil)
    }

    @Test("Invalid time 00:-1 returns nil")
    func invalidNegativeMinute() {
        let result = Schedule.parseTime("00:-1")
        #expect(result == nil)
    }

    @Test("Invalid time with garbage returns nil or valid defaults")
    func garbageInput() {
        // "abc" parses as hour=0, minute=0 which is actually valid
        let result = Schedule.parseTime("abc")
        #expect(result != nil)
        #expect(result?.hour == 0)
        #expect(result?.minute == 0)
    }

    @Test("Invalid time 25:00 causes daily schedule to return nil")
    func invalidTimeCausesNilNextFire() {
        let s = Schedule.daily(time: "25:00")
        let from = date(2026, 3, 26, 10, 0)
        #expect(s.nextFireDate(after: from) == nil)
    }

    @Test("Invalid time 12:99 causes weekly schedule to return nil")
    func invalidTimeWeekly() {
        let s = Schedule.weekly(weekday: 1, time: "12:99")
        let from = date(2026, 3, 26, 10, 0)
        #expect(s.nextFireDate(after: from) == nil)
    }

    @Test("Invalid time 30:00 causes monthly schedule to return nil")
    func invalidTimeMonthly() {
        let s = Schedule.monthly(days: [1], time: "30:00")
        let from = date(2026, 3, 26, 10, 0)
        #expect(s.nextFireDate(after: from) == nil)
    }
}
