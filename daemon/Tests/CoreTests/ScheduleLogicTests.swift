import Testing
import Foundation
@testable import Core

// MARK: - Helper

private func makeTask(
    id: String = "task-1",
    schedule: Schedule = .everyMinute,
    enabled: Bool = true
) -> TaskDefinition {
    TaskDefinition(id: id, name: id, command: "echo hi", schedule: schedule, enabled: enabled)
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year; comps.month = month; comps.day = day
    comps.hour = hour; comps.minute = minute; comps.second = second
    return Calendar.current.date(from: comps)!
}

// MARK: - dueTasks

@Suite("ScheduleLogic.dueTasks")
struct DueTasksTests {
    @Test("Task with nextFire in the past is due")
    func pastFireDate() {
        let task = makeTask()
        let now = date(2026, 3, 26, 10, 30, 0)
        let fireDates = ["task-1": date(2026, 3, 26, 10, 29, 0)]
        let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: fireDates, at: now)
        #expect(due.map(\.id) == ["task-1"])
    }

    @Test("Task with nextFire exactly at now is due")
    func exactFireDate() {
        let task = makeTask()
        let now = date(2026, 3, 26, 10, 30, 0)
        let fireDates = ["task-1": now]
        let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: fireDates, at: now)
        #expect(due.map(\.id) == ["task-1"])
    }

    @Test("Task with nextFire in the future is not due")
    func futureFireDate() {
        let task = makeTask()
        let now = date(2026, 3, 26, 10, 30, 0)
        let fireDates = ["task-1": date(2026, 3, 26, 10, 31, 0)]
        let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: fireDates, at: now)
        #expect(due.isEmpty)
    }

    @Test("Disabled task is never due")
    func disabledTask() {
        let task = makeTask(enabled: false)
        let now = date(2026, 3, 26, 10, 30, 0)
        let fireDates = ["task-1": date(2026, 3, 26, 10, 29, 0)]
        let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: fireDates, at: now)
        #expect(due.isEmpty)
    }

    @Test("Task with no fire date entry is not due")
    func missingFireDate() {
        let task = makeTask()
        let now = date(2026, 3, 26, 10, 30, 0)
        let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: [:], at: now)
        #expect(due.isEmpty)
    }

    @Test("Mixed tasks: only due ones are returned")
    func mixedTasks() {
        let t1 = makeTask(id: "due-1")
        let t2 = makeTask(id: "not-yet")
        let t3 = makeTask(id: "due-2")
        let t4 = makeTask(id: "disabled", enabled: false)
        let now = date(2026, 3, 26, 10, 30, 0)
        let fireDates: [String: Date] = [
            "due-1": date(2026, 3, 26, 10, 29, 0),
            "not-yet": date(2026, 3, 26, 10, 31, 0),
            "due-2": date(2026, 3, 26, 10, 30, 0),
            "disabled": date(2026, 3, 26, 10, 29, 0),
        ]
        let due = ScheduleLogic.dueTasks(from: [t1, t2, t3, t4], nextFireDates: fireDates, at: now)
        #expect(due.map(\.id) == ["due-1", "due-2"])
    }

    @Test("Empty tasks returns empty")
    func emptyTasks() {
        let due = ScheduleLogic.dueTasks(from: [], nextFireDates: [:], at: Date())
        #expect(due.isEmpty)
    }
}

// MARK: - calculateNextFireDates

@Suite("ScheduleLogic.calculateNextFireDates")
struct CalculateNextFireDatesTests {
    @Test("Every-minute task gets next minute boundary")
    func everyMinute() {
        let task = makeTask(schedule: .everyMinute)
        let now = date(2026, 3, 26, 10, 30, 15)
        let dates = ScheduleLogic.calculateNextFireDates(for: [task], after: now)
        #expect(dates["task-1"] == date(2026, 3, 26, 10, 31, 0))
    }

    @Test("Disabled task is excluded")
    func disabledExcluded() {
        let task = makeTask(enabled: false)
        let now = date(2026, 3, 26, 10, 30, 0)
        let dates = ScheduleLogic.calculateNextFireDates(for: [task], after: now)
        #expect(dates.isEmpty)
    }

    @Test("Multiple tasks with different schedules")
    func multipleTasks() {
        let t1 = makeTask(id: "minutely", schedule: .everyMinute)
        let t2 = makeTask(id: "hourly", schedule: .hourly(minute: 0))
        let t3 = makeTask(id: "off", schedule: .everyMinute, enabled: false)
        let now = date(2026, 3, 26, 10, 30, 0)
        let dates = ScheduleLogic.calculateNextFireDates(for: [t1, t2, t3], after: now)

        #expect(dates.count == 2)
        #expect(dates["minutely"] == date(2026, 3, 26, 10, 31, 0))
        #expect(dates["hourly"] == date(2026, 3, 26, 11, 0, 0))
        #expect(dates["off"] == nil)
    }

    @Test("Empty tasks returns empty")
    func emptyTasks() {
        let dates = ScheduleLogic.calculateNextFireDates(for: [], after: Date())
        #expect(dates.isEmpty)
    }
}

// MARK: - Scheduling cycle simulation

@Suite("Scheduling cycle simulation")
struct SchedulingCycleTests {
    @Test("Every-minute task fires once per minute across 5 minutes")
    func everyMinuteCycle() {
        let task = makeTask(schedule: .everyMinute)
        let tasks = [task]
        let start = date(2026, 3, 26, 10, 0, 0)

        var fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: start)
        var firedCount = 0

        // 10秒刻みで5分間シミュレーション (30ティック)
        for tick in 1...30 {
            let now = start.addingTimeInterval(Double(tick) * 10)
            let due = ScheduleLogic.dueTasks(from: tasks, nextFireDates: fireDates, at: now)
            firedCount += due.count
            fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: now)
        }

        #expect(firedCount == 5)
    }

    @Test("Daily task fires exactly once per day")
    func dailyCycle() {
        let task = makeTask(id: "daily", schedule: .daily(time: "09:00"))
        let tasks = [task]
        let start = date(2026, 3, 26, 8, 55, 0)

        var fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: start)
        var firedMinutes: [Int] = []

        // 1分刻みで30分間シミュレーション
        for tick in 1...30 {
            let now = start.addingTimeInterval(Double(tick) * 60)
            let due = ScheduleLogic.dueTasks(from: tasks, nextFireDates: fireDates, at: now)
            if !due.isEmpty {
                firedMinutes.append(tick)
            }
            fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: now)
        }

        // 09:00 を過ぎた最初のティック (tick=5, つまり 09:00) で1回だけ発火
        #expect(firedMinutes.count == 1)
        #expect(firedMinutes.first == 5)
    }

    @Test("Disabled task never fires in cycle")
    func disabledNeverFires() {
        let task = makeTask(schedule: .everyMinute, enabled: false)
        let start = date(2026, 3, 26, 10, 0, 0)

        var fireDates = ScheduleLogic.calculateNextFireDates(for: [task], after: start)
        var firedCount = 0

        for tick in 1...10 {
            let now = start.addingTimeInterval(Double(tick) * 60)
            let due = ScheduleLogic.dueTasks(from: [task], nextFireDates: fireDates, at: now)
            firedCount += due.count
            fireDates = ScheduleLogic.calculateNextFireDates(for: [task], after: now)
        }

        #expect(firedCount == 0)
    }

    @Test("Hourly task fires once per hour")
    func hourlyCycle() {
        let task = makeTask(id: "hourly", schedule: .hourly(minute: 15))
        let tasks = [task]
        let start = date(2026, 3, 26, 10, 0, 0)

        var fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: start)
        var firedCount = 0

        // 5分刻みで2時間シミュレーション (24ティック)
        for tick in 1...24 {
            let now = start.addingTimeInterval(Double(tick) * 300)
            let due = ScheduleLogic.dueTasks(from: tasks, nextFireDates: fireDates, at: now)
            firedCount += due.count
            fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: now)
        }

        // 10:15 と 11:15 の2回発火
        #expect(firedCount == 2)
    }

    @Test("Multiple tasks fire independently")
    func multipleTasksCycle() {
        let t1 = makeTask(id: "fast", schedule: .everyMinute)
        let t2 = makeTask(id: "slow", schedule: .hourly(minute: 3))
        let tasks = [t1, t2]
        let start = date(2026, 3, 26, 10, 0, 0)

        var fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: start)
        var fastCount = 0
        var slowCount = 0

        // 1分刻みで5分間
        for tick in 1...5 {
            let now = start.addingTimeInterval(Double(tick) * 60)
            let due = ScheduleLogic.dueTasks(from: tasks, nextFireDates: fireDates, at: now)
            for t in due {
                if t.id == "fast" { fastCount += 1 }
                if t.id == "slow" { slowCount += 1 }
            }
            fireDates = ScheduleLogic.calculateNextFireDates(for: tasks, after: now)
        }

        #expect(fastCount == 5)
        #expect(slowCount == 1) // 10:03 で発火
    }
}
