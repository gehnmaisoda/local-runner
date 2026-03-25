import Foundation

/// アプリ全体で使用するファイルパスの一元管理。
public enum ConfigPaths: Sendable {
    #if DEV
    private static let appName = "LocalRunner-Dev"
    private static let configDirName = "local-runner-dev"
    #else
    private static let appName = "LocalRunner"
    private static let configDirName = "local-runner"
    #endif

    // MARK: - Config (~/.config/local-runner/)

    public static var configDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/\(configDirName)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var tasksDirectory: URL {
        let dir = configDirectory.appendingPathComponent("tasks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var settingsFile: URL {
        configDirectory.appendingPathComponent("settings.yaml")
    }

    // MARK: - Data (~/Library/Application Support/LocalRunner/)

    public static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(appName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var logsDirectory: URL {
        let dir = dataDirectory.appendingPathComponent("logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var socketPath: String {
        dataDirectory.appendingPathComponent("daemon.sock").path
    }
}
