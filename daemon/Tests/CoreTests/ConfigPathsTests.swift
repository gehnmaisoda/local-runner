import Testing
import Foundation
@testable import Core

@Suite("ConfigPaths - path construction")
struct ConfigPathsPathTests {
    @Test("configDirectory is under ~/.config/")
    func configDirectoryPath() {
        let dir = ConfigPaths.configDirectory
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(dir.path.hasPrefix(home))
        #expect(dir.path.contains(".config/"))
        #expect(dir.path.contains(ConfigPaths.configDirName))
    }

    @Test("tasksDirectory is under configDirectory")
    func tasksDirectoryPath() {
        let tasks = ConfigPaths.tasksDirectory
        let config = ConfigPaths.configDirectory
        #expect(tasks.path.hasPrefix(config.path))
        #expect(tasks.lastPathComponent == "tasks")
    }

    @Test("settingsFile is in configDirectory")
    func settingsFilePath() {
        let settings = ConfigPaths.settingsFile
        let config = ConfigPaths.configDirectory
        #expect(settings.path.hasPrefix(config.path))
        #expect(settings.lastPathComponent == "settings.yaml")
    }

    @Test("dataDirectory is under Application Support")
    func dataDirectoryPath() {
        let dir = ConfigPaths.dataDirectory
        #expect(dir.path.contains("Application Support"))
        #expect(dir.path.contains(ConfigPaths.appName))
    }

    @Test("logsDirectory is under dataDirectory")
    func logsDirectoryPath() {
        let logs = ConfigPaths.logsDirectory
        let data = ConfigPaths.dataDirectory
        #expect(logs.path.hasPrefix(data.path))
        #expect(logs.lastPathComponent == "logs")
    }

    @Test("socketPath is under dataDirectory")
    func socketPathLocation() {
        let sockPath = ConfigPaths.socketPath
        let dataPath = ConfigPaths.dataDirectory.path
        #expect(sockPath.hasPrefix(dataPath))
        #expect(sockPath.hasSuffix("daemon.sock"))
    }

    @Test("sleepStateFile is under dataDirectory")
    func sleepStateFilePath() {
        let file = ConfigPaths.sleepStateFile
        let data = ConfigPaths.dataDirectory
        #expect(file.path.hasPrefix(data.path))
        #expect(file.lastPathComponent == "sleep_started_at")
    }

    @Test("heartbeatFile is under dataDirectory")
    func heartbeatFilePath() {
        let file = ConfigPaths.heartbeatFile
        let data = ConfigPaths.dataDirectory
        #expect(file.path.hasPrefix(data.path))
        #expect(file.lastPathComponent == "heartbeat")
    }
}

@Suite("ConfigPaths - directory creation")
struct ConfigPathsDirectoryCreationTests {
    @Test("configDirectory creates the directory on access")
    func configDirectoryCreated() {
        let dir = ConfigPaths.configDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("tasksDirectory creates the directory on access")
    func tasksDirectoryCreated() {
        let dir = ConfigPaths.tasksDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("dataDirectory creates the directory on access")
    func dataDirectoryCreated() {
        let dir = ConfigPaths.dataDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("logsDirectory creates the directory on access")
    func logsDirectoryCreated() {
        let dir = ConfigPaths.logsDirectory
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("ensureDirectory is idempotent")
    func ensureDirectoryIdempotent() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lr-test-idempotent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create twice; should not fail
        ConfigPaths.ensureDirectory(at: tmp)
        ConfigPaths.ensureDirectory(at: tmp)

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: tmp.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }
}

#if DEV
@Suite("ConfigPaths - dev mode")
struct ConfigPathsDevTests {
    @Test("Dev mode uses different app name")
    func devAppName() {
        #expect(ConfigPaths.appName == "LocalRunner-Dev")
        #expect(ConfigPaths.configDirName == "local-runner-dev")
    }
}
#else
@Suite("ConfigPaths - production mode")
struct ConfigPathsProdTests {
    @Test("Production mode uses standard app name")
    func prodAppName() {
        #expect(ConfigPaths.appName == "LocalRunner")
        #expect(ConfigPaths.configDirName == "local-runner")
    }
}
#endif
