import Testing
import Foundation
@testable import Core

@Suite("GlobalSettings - Slack fields")
struct GlobalSettingsSlackTests {
    @Test("Slack fields default to nil")
    func slackDefaults() {
        let settings = GlobalSettings()
        #expect(settings.slackBotToken == nil)
        #expect(settings.slackChannel == nil)
    }

    @Test("Slack fields can be set via init")
    func slackInit() {
        let settings = GlobalSettings(slackBotToken: "xoxb-test", slackChannel: "C123")
        #expect(settings.slackBotToken == "xoxb-test")
        #expect(settings.slackChannel == "C123")
    }

    @Test("GlobalSettings JSON roundtrip preserves Slack fields")
    func jsonRoundtrip() throws {
        let settings = GlobalSettings(slackBotToken: "xoxb-abc", slackChannel: "C456", slackChannelName: "general", defaultTimeout: 120)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: data)
        #expect(decoded.slackBotToken == "xoxb-abc")
        #expect(decoded.slackChannel == "C456")
        #expect(decoded.slackChannelName == "general")
        #expect(decoded.defaultTimeout == 120)
    }

    @Test("JSON uses snake_case keys")
    func snakeCaseKeys() throws {
        let settings = GlobalSettings(slackBotToken: "xoxb-x", slackChannel: "C1", slackChannelName: "test")
        let data = try JSONEncoder().encode(settings)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("slack_bot_token"))
        #expect(json.contains("slack_channel"))
        #expect(json.contains("slack_channel_name"))
    }
}

@Suite("GlobalSettings.effectiveDefaultTimeout")
struct GlobalSettingsEffectiveTimeoutTests {
    @Test("Returns custom value when defaultTimeout is set")
    func customValue() {
        let settings = GlobalSettings(defaultTimeout: 60)
        #expect(settings.effectiveDefaultTimeout == 60)
    }

    @Test("Falls back to defaultTimeoutValue when defaultTimeout is nil")
    func fallbackToDefault() {
        let settings = GlobalSettings()
        #expect(settings.effectiveDefaultTimeout == GlobalSettings.defaultTimeoutValue)
        #expect(settings.effectiveDefaultTimeout == 3600)
    }

    @Test("defaultTimeoutValue is 3600")
    func staticDefault() {
        #expect(GlobalSettings.defaultTimeoutValue == 3600)
    }
}
