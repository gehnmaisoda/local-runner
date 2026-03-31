import Testing
import Foundation
@testable import Core
@testable import DaemonLib

// All WakeDetector tests must run serially because they share the same
// heartbeat/sleep-state files on the real file system.
@Suite("WakeDetector", .serialized)
struct WakeDetectorAllTests {

    /// Clean up shared files before each logical group.
    private func cleanupFiles() {
        try? FileManager.default.removeItem(at: ConfigPaths.heartbeatFile)
        try? FileManager.default.removeItem(at: ConfigPaths.sleepStateFile)
    }

    // MARK: - Heartbeat file tests

    @Test("Heartbeat file path is under data directory")
    func heartbeatPath() {
        let path = ConfigPaths.heartbeatFile
        #expect(path.path.contains(ConfigPaths.appName))
        #expect(path.lastPathComponent == "heartbeat")
    }

    @Test("Sleep state file path is under data directory")
    func sleepStatePath() {
        let path = ConfigPaths.sleepStateFile
        #expect(path.path.contains(ConfigPaths.appName))
        #expect(path.lastPathComponent == "sleep_started_at")
    }

    @Test("Heartbeat file contains a valid timestamp when written")
    func heartbeatContent() {
        let file = ConfigPaths.heartbeatFile
        let timestamp = Date().timeIntervalSince1970
        let str = String(timestamp)
        try? str.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let data = try? Data(contentsOf: file)
        #expect(data != nil)
        let readStr = String(data: data!, encoding: .utf8)
        #expect(readStr != nil)
        let readTimestamp = TimeInterval(readStr!)
        #expect(readTimestamp != nil)
        #expect(abs(readTimestamp! - timestamp) < 1.0)
    }

    @Test("Sleep state file contains a valid timestamp when written")
    func sleepStateContent() {
        let file = ConfigPaths.sleepStateFile
        let timestamp = Date().timeIntervalSince1970
        let str = String(timestamp)
        try? str.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let data = try? Data(contentsOf: file)
        #expect(data != nil)
        let readStr = String(data: data!, encoding: .utf8)
        #expect(readStr != nil)
        let readTimestamp = TimeInterval(readStr!)
        #expect(readTimestamp != nil)
        #expect(abs(readTimestamp! - timestamp) < 1.0)
    }

    // MARK: - Gap detection logic

    @Test("No heartbeat file means no gap detected")
    func noHeartbeatFile() {
        cleanupFiles()
        defer { cleanupFiles() }

        let detector = WakeDetector { _ in }
        let gap = detector.detectStartupGap()
        #expect(gap == nil)
    }

    @Test("Recent heartbeat means no gap detected")
    func recentHeartbeat() {
        cleanupFiles()
        defer { cleanupFiles() }

        let recentTime = Date().addingTimeInterval(-30)
        let str = String(recentTime.timeIntervalSince1970)
        try? str.write(to: ConfigPaths.heartbeatFile, atomically: true, encoding: .utf8)

        let detector = WakeDetector { _ in }
        let gap = detector.detectStartupGap()
        #expect(gap == nil)
    }

    @Test("Old heartbeat (> 3x interval) means gap detected")
    func oldHeartbeat() {
        cleanupFiles()
        defer { cleanupFiles() }

        let oldTime = Date().addingTimeInterval(-600)
        let str = String(oldTime.timeIntervalSince1970)
        try? str.write(to: ConfigPaths.heartbeatFile, atomically: true, encoding: .utf8)

        let detector = WakeDetector { _ in }
        let gap = detector.detectStartupGap()
        #expect(gap != nil)
        if let gap = gap {
            #expect(abs(gap.timeIntervalSince(oldTime)) < 2.0)
        }
    }

    @Test("Sleep state file takes priority over heartbeat")
    func sleepStatePriority() {
        cleanupFiles()
        defer { cleanupFiles() }

        let sleepTime = Date().addingTimeInterval(-300)
        let sleepStr = String(sleepTime.timeIntervalSince1970)
        try? sleepStr.write(to: ConfigPaths.sleepStateFile, atomically: true, encoding: .utf8)

        let recentStr = String(Date().addingTimeInterval(-10).timeIntervalSince1970)
        try? recentStr.write(to: ConfigPaths.heartbeatFile, atomically: true, encoding: .utf8)

        let detector = WakeDetector { _ in }
        let gap = detector.detectStartupGap()
        #expect(gap != nil)
        if let gap = gap {
            #expect(abs(gap.timeIntervalSince(sleepTime)) < 2.0)
        }
    }

    @Test("detectStartupGap clears sleep state file after reading")
    func clearsAfterReading() {
        cleanupFiles()
        defer { cleanupFiles() }

        let sleepTime = Date().addingTimeInterval(-300)
        let str = String(sleepTime.timeIntervalSince1970)
        try? str.write(to: ConfigPaths.sleepStateFile, atomically: true, encoding: .utf8)

        let detector = WakeDetector { _ in }
        let _ = detector.detectStartupGap()

        #expect(!FileManager.default.fileExists(atPath: ConfigPaths.sleepStateFile.path))
    }

    @Test("Corrupt heartbeat file is treated as no heartbeat")
    func corruptHeartbeatFile() {
        cleanupFiles()
        defer { cleanupFiles() }

        try? "not-a-number".write(to: ConfigPaths.heartbeatFile, atomically: true, encoding: .utf8)

        let detector = WakeDetector { _ in }
        let gap = detector.detectStartupGap()
        #expect(gap == nil)
    }
}
