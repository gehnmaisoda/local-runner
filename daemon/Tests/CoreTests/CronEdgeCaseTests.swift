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

// MARK: - Weekday handling in cron

@Suite("CronExpression weekday edge cases")
struct CronWeekdayTests {
    @Test("Sunday as 0 matches correctly")
    func sundayAsZero() throws {
        // "0 9 * * 0" = every Sunday at 09:00
        let cron = try CronExpression("0 9 * * 0")
        // 2026-03-26 is Thursday → next Sunday is 2026-03-29
        let from = date(2026, 3, 26, 10, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 29)
        #expect(cal.component(.hour, from: next!) == 9)
        // Verify it's actually a Sunday (Calendar weekday 1 = Sunday)
        #expect(cal.component(.weekday, from: next!) == 1)
    }

    @Test("Sunday as 7 also matches correctly")
    func sundayAsSeven() throws {
        // "0 9 * * 7" = every Sunday at 09:00 (7 is also Sunday in many cron implementations)
        let cron = try CronExpression("0 9 * * 7")
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        // Should also find Sunday 2026-03-29
        #expect(cal.component(.weekday, from: next!) == 1)
        #expect(cal.component(.day, from: next!) == 29)
    }

    @Test("Weekday 1 = Monday")
    func mondayCron() throws {
        let cron = try CronExpression("0 9 * * 1")
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        // Next Monday = 2026-03-30
        #expect(cal.component(.day, from: next!) == 30)
        #expect(cal.component(.weekday, from: next!) == 2) // Calendar: Monday=2
    }

    @Test("Weekday 6 = Saturday")
    func saturdayCron() throws {
        let cron = try CronExpression("0 9 * * 6")
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        // Next Saturday = 2026-03-28
        #expect(cal.component(.day, from: next!) == 28)
        #expect(cal.component(.weekday, from: next!) == 7) // Calendar: Saturday=7
    }

    @Test("Multiple weekdays in cron: Mon,Wed,Fri")
    func multipleWeekdays() throws {
        let cron = try CronExpression("0 9 * * 1,3,5")
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        // Next match: Friday 2026-03-27
        #expect(cal.component(.day, from: next!) == 27)
    }
}

// MARK: - Day-of-month and day-of-week interaction

@Suite("CronExpression day matching logic")
struct CronDayMatchingTests {
    @Test("Specific day-of-month with wildcard weekday")
    func specificDayWildcardWeekday() throws {
        // "0 9 15 * *" = 15th of every month at 09:00
        let cron = try CronExpression("0 9 15 * *")
        let from = date(2026, 3, 10, 0, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.day, from: next!) == 15)
        #expect(cal.component(.month, from: next!) == 3)
    }

    @Test("Wildcard day-of-month with specific weekday")
    func wildcardDaySpecificWeekday() throws {
        // "0 9 * * 5" = every Friday at 09:00
        let cron = try CronExpression("0 9 * * 5")
        let from = date(2026, 3, 26, 10, 0) // Thursday
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.weekday, from: next!) == 6) // Calendar: Friday=6
    }

    @Test("Both day-of-month and weekday restricted uses AND logic")
    func bothRestricted() throws {
        // "0 9 15 * 1" = 15th AND Monday (current AND implementation)
        // From 2026-03-01: need a day that is both the 15th and a Monday
        // 2026-06-15 is Monday
        let cron = try CronExpression("0 9 15 * 1")
        let from = date(2026, 3, 1, 0, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        let comps = cal.dateComponents([.day, .weekday], from: next!)
        #expect(comps.day == 15)
        #expect(comps.weekday == 2) // Monday in Calendar
    }

    @Test("Feb 29 in cron works on leap year")
    func feb29LeapYear() throws {
        // "0 0 29 2 *" = Feb 29
        let cron = try CronExpression("0 0 29 2 *")
        let from = date(2027, 1, 1, 0, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        // Next leap year from 2027 is 2028
        #expect(cal.component(.year, from: next!) == 2028)
        #expect(cal.component(.month, from: next!) == 2)
        #expect(cal.component(.day, from: next!) == 29)
    }
}

// MARK: - CronField parse edge cases

@Suite("CronField parse edge cases")
struct CronFieldEdgeCaseTests {
    @Test("Step of 1 expands to all values")
    func stepOfOne() throws {
        let field = try CronField.parse("*/1", range: 0...59)
        for v in 0...59 { #expect(field.matches(v)) }
    }

    @Test("Step of 0 throws error")
    func stepOfZero() {
        #expect(throws: CronError.self) {
            _ = try CronField.parse("*/0", range: 0...59)
        }
    }

    @Test("Start/step syntax: 5/15 means start at 5, step 15")
    func startStep() throws {
        let field = try CronField.parse("5/15", range: 0...59)
        #expect(field.matches(5))
        #expect(field.matches(20))
        #expect(field.matches(35))
        #expect(field.matches(50))
        #expect(!field.matches(0))
        #expect(!field.matches(15))
    }

    @Test("Combined list with range and step: 1,10-15,*/30")
    func combinedExpression() throws {
        let field = try CronField.parse("1,10-15,*/30", range: 0...59)
        #expect(field.matches(1))
        for v in 10...15 { #expect(field.matches(v)) }
        #expect(field.matches(0))
        #expect(field.matches(30))
        #expect(!field.matches(2))
        #expect(!field.matches(16))
    }

    @Test("Range where start equals end is single value")
    func singleValueRange() throws {
        let field = try CronField.parse("5-5", range: 0...59)
        #expect(field.matches(5))
        #expect(!field.matches(4))
        #expect(!field.matches(6))
    }
}

// MARK: - CronExpression month handling

@Suite("CronExpression month edge cases")
struct CronMonthTests {
    @Test("Specific month: only fires in that month")
    func specificMonth() throws {
        // "0 0 1 6 *" = June 1st
        let cron = try CronExpression("0 0 1 6 *")
        let from = date(2026, 3, 1, 0, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.month, from: next!) == 6)
        #expect(cal.component(.day, from: next!) == 1)
    }

    @Test("Year boundary: Dec → Jan")
    func yearBoundary() throws {
        // "0 0 1 1 *" = January 1st
        let cron = try CronExpression("0 0 1 1 *")
        let from = date(2026, 6, 1, 0, 0)
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        #expect(cal.component(.year, from: next!) == 2027)
        #expect(cal.component(.month, from: next!) == 1)
    }

    @Test("Every minute fires 60 times per hour")
    func everyMinuteFrequency() throws {
        let cron = try CronExpression("* * * * *")
        var current = date(2026, 3, 26, 10, 0, 0)
        var count = 0
        for _ in 0..<60 {
            guard let next = cron.nextDate(after: current) else { break }
            count += 1
            current = next
        }
        #expect(count == 60)
        // Should end at 11:00
        #expect(cal.component(.hour, from: current) == 11)
        #expect(cal.component(.minute, from: current) == 0)
    }
}
