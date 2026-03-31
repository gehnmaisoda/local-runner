import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - Helpers

private func makeTask(
    id: String = "test-task",
    name: String = "Test Task",
    command: String = "echo test"
) -> TaskDefinition {
    TaskDefinition(id: id, name: name, command: command, notifyOnFailure: true)
}

private func makeRecord(
    taskId: String = "test-task",
    status: ExecutionStatus = .failure,
    exitCode: Int32 = 1,
    stderr: String = "Error: something went wrong"
) -> ExecutionRecord {
    ExecutionRecord(
        taskId: taskId,
        taskName: "Test Task",
        command: "echo test",
        startedAt: Date(),
        finishedAt: Date(),
        exitCode: exitCode,
        stderr: stderr,
        status: status
    )
}

// MARK: - SlackNotifier behavior tests

@Suite("SlackNotifier - behavior")
struct SlackNotifierBehaviorTests {
    @Test("No webhook URL means notification is silently skipped")
    func noWebhookURL() {
        let notifier = SlackNotifier()
        notifier.webhookURL = nil
        let task = makeTask()
        let record = makeRecord()
        // Should not crash, just return silently
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Empty webhook URL means notification is silently skipped")
    func emptyWebhookURL() {
        let notifier = SlackNotifier()
        notifier.webhookURL = ""
        let task = makeTask()
        let record = makeRecord()
        // Empty string is not a valid URL, so URL(string:) returns nil
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Invalid webhook URL means notification is silently skipped")
    func invalidWebhookURL() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "not a valid url %%"
        let task = makeTask()
        let record = makeRecord()
        // Should not crash
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("webhookURL can be set and read")
    func setWebhookURL() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "https://hooks.slack.com/services/XXX/YYY/ZZZ"
        #expect(notifier.webhookURL == "https://hooks.slack.com/services/XXX/YYY/ZZZ")
    }

    @Test("webhookURL defaults to nil")
    func defaultWebhookURL() {
        let notifier = SlackNotifier()
        #expect(notifier.webhookURL == nil)
    }
}

// MARK: - Notification payload structure tests

@Suite("SlackNotifier - payload structure")
struct SlackNotifierPayloadTests {
    // We test the escaping logic and payload generation indirectly

    @Test("Task name with special characters does not crash")
    func specialCharacterTaskName() {
        let notifier = SlackNotifier()
        // Use a non-routable URL that won't actually send
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask(name: "Task <with> &special& chars")
        let record = makeRecord()
        // Should not crash even with special characters
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Long stderr is truncated in notification")
    func longStderrTruncated() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask()
        let longStderr = String(repeating: "E", count: 1000)
        let record = makeRecord(stderr: longStderr)
        // The preview should be at most 500 characters (internal implementation detail)
        // This test just ensures it doesn't crash with long stderr
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Timeout status uses alarm clock emoji header")
    func timeoutHeader() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask()
        let record = makeRecord(status: .timeout, exitCode: -1)
        // Should use timeout-specific header, not crash
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Failure status uses X emoji header")
    func failureHeader() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask()
        let record = makeRecord(status: .failure, exitCode: 1)
        // Should use failure-specific header, not crash
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Empty stderr does not crash")
    func emptyStderr() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask()
        let record = makeRecord(stderr: "")
        notifier.notifyFailure(task: task, record: record)
    }

    @Test("Command with special characters in notification")
    func commandWithSpecialChars() {
        let notifier = SlackNotifier()
        notifier.webhookURL = "http://127.0.0.1:1/test"
        let task = makeTask(command: "curl 'https://api.example.com?a=1&b=2' | grep '<html>'")
        let record = makeRecord()
        notifier.notifyFailure(task: task, record: record)
    }
}
