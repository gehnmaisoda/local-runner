import Testing
@testable import Core

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
