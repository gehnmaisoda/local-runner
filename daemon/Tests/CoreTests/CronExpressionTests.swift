import Testing
import Foundation
@testable import Core

@Suite("CronField parsing")
struct CronFieldTests {
    @Test("Wildcard matches everything")
    func wildcard() throws {
        let field = try CronField.parse("*", range: 0...59)
        #expect(field == .any)
        #expect(field.matches(0))
        #expect(field.matches(30))
        #expect(field.matches(59))
    }

    @Test("Single value")
    func singleValue() throws {
        let field = try CronField.parse("5", range: 0...59)
        #expect(field.matches(5))
        #expect(!field.matches(6))
    }

    @Test("List of values")
    func list() throws {
        let field = try CronField.parse("1,15,30", range: 0...59)
        #expect(field.matches(1))
        #expect(field.matches(15))
        #expect(field.matches(30))
        #expect(!field.matches(2))
    }

    @Test("Range")
    func range() throws {
        let field = try CronField.parse("10-15", range: 0...59)
        for v in 10...15 { #expect(field.matches(v)) }
        #expect(!field.matches(9))
        #expect(!field.matches(16))
    }

    @Test("Step with wildcard")
    func stepWildcard() throws {
        let field = try CronField.parse("*/15", range: 0...59)
        #expect(field.matches(0))
        #expect(field.matches(15))
        #expect(field.matches(30))
        #expect(field.matches(45))
        #expect(!field.matches(1))
    }

    @Test("Step with range")
    func stepRange() throws {
        let field = try CronField.parse("1-10/3", range: 0...59)
        #expect(field.matches(1))
        #expect(field.matches(4))
        #expect(field.matches(7))
        #expect(field.matches(10))
        #expect(!field.matches(2))
    }

    @Test("Invalid field throws")
    func invalidField() {
        #expect(throws: CronError.self) {
            _ = try CronField.parse("abc", range: 0...59)
        }
    }
}

@Suite("CronExpression parsing")
struct CronExpressionTests {
    @Test("Parse standard 5-field expression")
    func parseStandard() throws {
        let cron = try CronExpression("0 3 * * *")
        #expect(cron.minute.matches(0))
        #expect(!cron.minute.matches(1))
        #expect(cron.hour.matches(3))
        #expect(!cron.hour.matches(4))
    }

    @Test("Invalid format throws")
    func invalidFormat() {
        #expect(throws: CronError.self) {
            _ = try CronExpression("0 3 *")
        }
    }

    @Test("Next date for daily at 03:00")
    func nextDateDaily() throws {
        let cron = try CronExpression("0 3 * * *")
        let cal = Calendar.current
        // 2026-03-25 10:00 から次は 2026-03-26 03:00
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 25
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let from = cal.date(from: comps)!
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        let nextComps = cal.dateComponents([.month, .day, .hour, .minute], from: next!)
        #expect(nextComps.month == 3)
        #expect(nextComps.day == 26)
        #expect(nextComps.hour == 3)
        #expect(nextComps.minute == 0)
    }

    @Test("Next date for every 15 minutes")
    func nextDateEvery15() throws {
        let cron = try CronExpression("*/15 * * * *")
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 1; comps.day = 1
        comps.hour = 12; comps.minute = 7; comps.second = 0
        let from = cal.date(from: comps)!
        let next = cron.nextDate(after: from)
        #expect(next != nil)
        let nextComps = cal.dateComponents([.hour, .minute], from: next!)
        #expect(nextComps.hour == 12)
        #expect(nextComps.minute == 15)
    }
}

@Suite("Schedule next fire date")
struct ScheduleTests {
    @Test("Every minute returns next minute")
    func everyMinute() {
        let schedule = Schedule.everyMinute
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 25
        comps.hour = 10; comps.minute = 30; comps.second = 0
        let from = cal.date(from: comps)!
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        let nextMin = cal.component(.minute, from: next!)
        #expect(nextMin == 31)
    }

    @Test("Daily schedule returns correct time")
    func daily() {
        let schedule = Schedule.daily(time: "09:00")
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 25
        comps.hour = 10; comps.minute = 0; comps.second = 0
        let from = cal.date(from: comps)!
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        let nextComps = cal.dateComponents([.day, .hour, .minute], from: next!)
        #expect(nextComps.day == 26)
        #expect(nextComps.hour == 9)
        #expect(nextComps.minute == 0)
    }

    @Test("Hourly schedule returns correct minute")
    func hourly() {
        let schedule = Schedule.hourly(minute: 15)
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 3; comps.day = 25
        comps.hour = 10; comps.minute = 20; comps.second = 0
        let from = cal.date(from: comps)!
        let next = schedule.nextFireDate(after: from)
        #expect(next != nil)
        let nextComps = cal.dateComponents([.hour, .minute], from: next!)
        #expect(nextComps.hour == 11)
        #expect(nextComps.minute == 15)
    }

    @Test("Display text")
    func displayText() {
        #expect(Schedule.everyMinute.displayText == "毎分")
        #expect(Schedule.daily(time: "09:00").displayText == "毎日 09:00")
        #expect(Schedule.hourly(minute: 30).displayText == "毎時 30分")
        #expect(Schedule.weekly(weekday: 1, time: "10:00").displayText == "毎週月曜 10:00")
        #expect(Schedule.cron("0 3 * * *").displayText == "0 3 * * *")
    }
}
