import Testing
import Foundation
@testable import DaemonLib

@Suite("SlackTokenResolver")
struct SlackTokenResolverTests {
    @Test("Direct token wins over the command")
    func directTokenWins() {
        let token = SlackTokenResolver.resolve(token: "xoxb-direct", command: "ignored") { _ in "xoxb-from-command" }
        #expect(token == "xoxb-direct")
    }

    @Test("Command output is used when the direct token is empty")
    func commandFallback() {
        let token = SlackTokenResolver.resolve(token: "", command: "get-token") { command in
            #expect(command == "get-token")
            return "xoxb-from-command\n"
        }
        #expect(token == "xoxb-from-command")
    }

    @Test("Returns nil when neither is set")
    func nothingConfigured() {
        #expect(SlackTokenResolver.resolve(token: nil, command: "  ") { _ in "unused" } == nil)
        #expect(!SlackTokenResolver.isConfigured(token: nil, command: nil))
        #expect(!SlackTokenResolver.isConfigured(token: " ", command: ""))
    }

    @Test("Command-only settings count as configured")
    func commandOnlyIsConfigured() {
        #expect(SlackTokenResolver.isConfigured(token: nil, command: "get-token"))
    }

    @Test("Returns nil when the command fails or prints nothing")
    func commandFailure() {
        #expect(SlackTokenResolver.resolve(token: nil, command: "get-token") { _ in nil } == nil)
        #expect(SlackTokenResolver.resolve(token: nil, command: "get-token") { _ in "\n" } == nil)
    }

    @Test("runCommand returns stdout of a successful command")
    func runCommandSuccess() {
        #expect(SlackTokenResolver.runCommand("printf xoxb-shell") == "xoxb-shell")
    }

    @Test("runCommand returns nil on non-zero exit")
    func runCommandNonZero() {
        #expect(SlackTokenResolver.runCommand("echo nope; exit 3") == nil)
    }

    @Test("runCommand gives up after the timeout")
    func runCommandTimeout() {
        let started = Date()
        #expect(SlackTokenResolver.runCommand("sleep 5", timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(started) < 4)
    }
}
