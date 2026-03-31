import Foundation
import os.log

/// アプリ全体で使用するファイルパスの一元管理。
public enum ConfigPaths: Sendable {
    #if DEV
    public static let appName = "LocalRunner-Dev"
    public static let configDirName = "local-runner-dev"
    #else
    public static let appName = "LocalRunner"
    public static let configDirName = "local-runner"
    #endif

    private static let logger = Logger(subsystem: "com.gehnmaisoda.local-runner", category: "ConfigPaths")

    /// Ensure a directory exists, logging a warning on failure.
    @discardableResult
    static func ensureDirectory(at dir: URL) -> URL {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.warning("Failed to create directory \(dir.path): \(error.localizedDescription)")
        }
        return dir
    }

    // MARK: - Config (~/.config/local-runner/)

    public static var configDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/\(configDirName)")
        return ensureDirectory(at: dir)
    }

    public static var tasksDirectory: URL {
        let dir = configDirectory.appendingPathComponent("tasks")
        return ensureDirectory(at: dir)
    }

    public static var settingsFile: URL {
        configDirectory.appendingPathComponent("settings.yaml")
    }

    // MARK: - Data (~/Library/Application Support/LocalRunner/)

    public static var dataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(appName)
        return ensureDirectory(at: dir)
    }

    public static var logsDirectory: URL {
        let dir = dataDirectory.appendingPathComponent("logs")
        return ensureDirectory(at: dir)
    }

    public static var socketPath: String {
        dataDirectory.appendingPathComponent("daemon.sock").path
    }

    /// スリープ開始時刻の永続化ファイル。
    public static var sleepStateFile: URL {
        dataDirectory.appendingPathComponent("sleep_started_at")
    }

    /// Heartbeat ファイル。デーモンが生存中であることを示す。
    public static var heartbeatFile: URL {
        dataDirectory.appendingPathComponent("heartbeat")
    }
}
