import Testing
import Foundation
@testable import Core

@Suite("Event schedule")
struct EventScheduleTests {
    @Test("Event schedule has no timer fire date")
    func noTimerFireDate() {
        let schedule = Schedule.event("circleback.meeting.completed")
        #expect(schedule.nextFireDate(after: Date()) == nil)
        #expect(schedule.displayText == "イベント: circleback.meeting.completed")
    }

    @Test("Event schedule survives Codable roundtrip")
    func codableRoundtrip() throws {
        let original = Schedule.event("demo.completed")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Schedule.self, from: data)
        #expect(decoded == original)
    }

    @Test("Event tasks are excluded from timer schedule calculation")
    func excludedFromTimerCalculation() {
        let task = TaskDefinition(
            id: "event-task", name: "Event task", command: "echo ok",
            schedule: .event("demo.completed")
        )
        #expect(ScheduleLogic.calculateNextFireDates(for: [task], after: Date()).isEmpty)
    }
}

@Suite("QueueConfiguration")
struct QueueConfigurationTests {
    @Test("Defaults stay within Cloudflare pull limits")
    func defaults() {
        let config = QueueConfiguration(accountId: "account", queueId: "queue", apiToken: "token")
        #expect(config.isValid)
        #expect(config.effectivePollInterval == 15)
        #expect(config.effectiveVisibilityTimeoutMilliseconds == 7_200_000)
        #expect(config.effectiveRetryDelay == 60)
    }

    @Test("JSON uses snake_case keys")
    func snakeCase() throws {
        let config = QueueConfiguration(accountId: "account", queueId: "queue", apiToken: "token")
        let data = try JSONEncoder().encode(config)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["account_id"] as? String == "account")
        #expect(object["queue_id"] as? String == "queue")
        #expect(object["api_token"] as? String == "token")
    }
}
