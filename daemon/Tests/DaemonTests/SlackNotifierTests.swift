import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - Helpers

private func makeTask(
    id: String = "test-task",
    name: String = "Test Task",
    command: String = "echo test",
    slackMentions: [String]? = nil
) -> TaskDefinition {
    TaskDefinition(id: id, name: name, command: command, slackNotify: true, slackMentions: slackMentions)
}

private func makeRecord(
    taskId: String = "test-task",
    status: ExecutionStatus = .failure,
    exitCode: Int32 = 1,
    stdout: String = "",
    stderr: String = "Error: something went wrong"
) -> ExecutionRecord {
    ExecutionRecord(
        taskId: taskId,
        taskName: "Test Task",
        command: "echo test",
        startedAt: Date(),
        finishedAt: Date(),
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        status: status
    )
}

// MARK: - SlackNotifier behavior tests

@Suite("SlackNotifier - behavior")
struct SlackNotifierBehaviorTests {
    @Test("No bot token means notification is silently skipped")
    func noBotToken() {
        let notifier = SlackNotifier()
        notifier.botToken = nil
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Empty bot token means notification is silently skipped")
    func emptyBotToken() {
        let notifier = SlackNotifier()
        notifier.botToken = ""
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("No channel means notification is silently skipped")
    func noChannel() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = nil
        let task = makeTask()
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("botToken can be set and read")
    func setBotToken() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test-token"
        #expect(notifier.botToken == "xoxb-test-token")
    }

    @Test("botToken defaults to nil")
    func defaultBotToken() {
        let notifier = SlackNotifier()
        #expect(notifier.botToken == nil)
    }

    @Test("channel defaults to nil")
    func defaultChannel() {
        let notifier = SlackNotifier()
        #expect(notifier.channel == nil)
    }
}

// MARK: - escapeSlack tests

@Suite("SlackNotifier - escapeSlack")
struct SlackEscapeTests {
    @Test("Ampersand is escaped")
    func ampersand() {
        #expect(SlackNotifier.escapeSlack("a & b") == "a &amp; b")
    }

    @Test("Less-than is escaped")
    func lessThan() {
        #expect(SlackNotifier.escapeSlack("<html>") == "&lt;html&gt;")
    }

    @Test("Greater-than is escaped")
    func greaterThan() {
        #expect(SlackNotifier.escapeSlack("a > b") == "a &gt; b")
    }

    @Test("Multiple special characters are all escaped")
    func multipleSpecialChars() {
        let input = "curl 'https://api.example.com?a=1&b=2' | grep '<html>'"
        let result = SlackNotifier.escapeSlack(input)
        #expect(!result.contains("&b"))
        #expect(result.contains("&amp;"))
        #expect(result.contains("&lt;"))
        #expect(result.contains("&gt;"))
    }

    @Test("String without special characters is unchanged")
    func noSpecialChars() {
        #expect(SlackNotifier.escapeSlack("hello world") == "hello world")
    }

    @Test("Empty string returns empty")
    func emptyString() {
        #expect(SlackNotifier.escapeSlack("") == "")
    }
}

// MARK: - Notification payload structure tests

@Suite("SlackNotifier - payload structure")
struct SlackNotifierPayloadTests {
    @Test("Task name with special characters does not crash")
    func specialCharacterTaskName() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask(name: "Task <with> &special& chars")
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Long stderr does not crash")
    func longStderr() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord(stderr: String(repeating: "E", count: 5000))
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Success status uses check mark emoji")
    func successStatus() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord(status: .success, exitCode: 0)
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Timeout status uses alarm clock emoji")
    func timeoutStatus() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord(status: .timeout, exitCode: -1)
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Mentions are included in notification")
    func withMentions() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask(slackMentions: ["<!channel>", "<@U123>"])
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Empty stderr and stdout does not crash")
    func emptyOutput() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask()
        let record = makeRecord(stderr: "")
        notifier.notifyCompletion(task: task, record: record)
    }

    @Test("Command with special characters in notification")
    func commandWithSpecialChars() {
        let notifier = SlackNotifier()
        notifier.botToken = "xoxb-test"
        notifier.channel = "C123"
        let task = makeTask(command: "curl 'https://api.example.com?a=1&b=2' | grep '<html>'")
        let record = makeRecord()
        notifier.notifyCompletion(task: task, record: record)
    }
}
