import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// MARK: - NetworkChecking protocol tests with mock

@Suite("NetworkChecking - mock implementation")
struct NetworkCheckingMockTests {
    @Test("MockNetworkMonitor starts connected by default")
    func defaultConnected() {
        let mock = MockNetworkMonitor()
        #expect(mock.isConnected)
    }

    @Test("simulateDisconnect sets isConnected to false")
    func disconnect() {
        let mock = MockNetworkMonitor()
        mock.simulateDisconnect()
        #expect(!mock.isConnected)
    }

    @Test("simulateRestore sets isConnected to true and fires callback")
    func restore() {
        let mock = MockNetworkMonitor()
        var callbackFired = false
        mock.onRestore = { callbackFired = true }

        mock.simulateDisconnect()
        mock.simulateRestore()

        #expect(mock.isConnected)
        #expect(callbackFired)
    }

    @Test("onRestore callback can be changed")
    func changeCallback() {
        let mock = MockNetworkMonitor()
        var count1 = 0
        var count2 = 0

        mock.onRestore = { count1 += 1 }
        mock.simulateRestore()
        #expect(count1 == 1)

        mock.onRestore = { count2 += 1 }
        mock.simulateRestore()
        #expect(count1 == 1) // old callback should not fire
        #expect(count2 == 1)
    }

    @Test("Multiple disconnect/restore cycles work correctly")
    func multipleCycles() {
        let mock = MockNetworkMonitor()
        var restoreCount = 0
        mock.onRestore = { restoreCount += 1 }

        for _ in 0..<5 {
            mock.simulateDisconnect()
            #expect(!mock.isConnected)
            mock.simulateRestore()
            #expect(mock.isConnected)
        }

        #expect(restoreCount == 5)
    }

    @Test("start and stop do not crash on mock")
    func startStop() {
        let mock = MockNetworkMonitor()
        mock.start()
        mock.stop()
        // Just verify no crash
        #expect(mock.isConnected)
    }

    @Test("onRestore is nil by default")
    func defaultCallbackNil() {
        let mock = MockNetworkMonitor()
        #expect(mock.onRestore == nil)
    }
}

// MARK: - NetworkMonitor (real) initialization

@Suite("NetworkMonitor - real implementation")
struct NetworkMonitorRealTests {
    @Test("Initial state is connected")
    func initialState() {
        let monitor = NetworkMonitor()
        #expect(monitor.isConnected)
    }

    @Test("onRestore is nil by default")
    func defaultCallback() {
        let monitor = NetworkMonitor()
        #expect(monitor.onRestore == nil)
    }

    @Test("Setting onRestore callback works")
    func setCallback() {
        let monitor = NetworkMonitor()
        var called = false
        monitor.onRestore = { called = true }
        #expect(monitor.onRestore != nil)
        // We can't easily test the callback fires without real network changes,
        // but we verify the setter works
        _ = called
    }

    @Test("start and stop do not crash")
    func startAndStop() {
        let monitor = NetworkMonitor()
        monitor.start()
        // Allow a brief moment for the handler to be set up
        Thread.sleep(forTimeInterval: 0.1)
        monitor.stop()
        // Just verify no crash
    }
}

// MARK: - NetworkChecking protocol conformance

@Suite("NetworkChecking - protocol")
struct NetworkCheckingProtocolTests {
    @Test("MockNetworkMonitor conforms to NetworkChecking")
    func mockConformance() {
        let checker: any NetworkChecking = MockNetworkMonitor()
        #expect(checker.isConnected)
    }

    @Test("NetworkMonitor conforms to NetworkChecking")
    func realConformance() {
        let checker: any NetworkChecking = NetworkMonitor()
        #expect(checker.isConnected)
    }

    @Test("Protocol can be used polymorphically")
    func polymorphic() {
        func checkNetwork(_ monitor: any NetworkChecking) -> Bool {
            return monitor.isConnected
        }

        let mock = MockNetworkMonitor()
        #expect(checkNetwork(mock))

        mock.simulateDisconnect()
        #expect(!checkNetwork(mock))
    }
}
