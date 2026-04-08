import Foundation
import Yams
import os.log

/// タスク定義。YAML ファイルとして ~/.config/local-runner/tasks/ に保存される。
public struct TaskDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public var description: String?
    public var command: String
    public var workingDirectory: String?
    public var schedule: Schedule
    public var enabled: Bool
    public var catchUp: Bool
    public var slackNotify: Bool
    public var slackMentions: [String]?
    public var timeout: Int?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        command: String,
        workingDirectory: String? = nil,
        schedule: Schedule = .daily(),
        enabled: Bool = true,
        catchUp: Bool = true,
        slackNotify: Bool = true,
        slackMentions: [String]? = nil,
        timeout: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.workingDirectory = workingDirectory
        self.schedule = schedule
        self.enabled = enabled
        self.catchUp = catchUp
        self.slackNotify = slackNotify
        self.slackMentions = slackMentions
        self.timeout = timeout
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, command
        case workingDirectory = "working_directory"
        case schedule, enabled
        case catchUp = "catch_up"
        case slackNotify = "slack_notify"
        case slackMentions = "slack_mentions"
        case timeout
    }

    /// 既存 YAML に slack_notify が存在しない場合のデフォルト値を提供する。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        command = try container.decode(String.self, forKey: .command)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        schedule = try container.decode(Schedule.self, forKey: .schedule)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        catchUp = try container.decode(Bool.self, forKey: .catchUp)
        slackNotify = try container.decodeIfPresent(Bool.self, forKey: .slackNotify) ?? true
        slackMentions = try container.decodeIfPresent([String].self, forKey: .slackMentions)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
    }
}

// MARK: - TaskStore

/// Errors that can occur when loading task definitions.
public enum TaskStoreError: Error, CustomStringConvertible {
    case directoryReadFailed(path: String, underlying: Error?)
    case fileReadFailed(filename: String, underlying: Error?)
    case yamlParseFailed(filename: String, underlying: Error)

    public var description: String {
        switch self {
        case .directoryReadFailed(let path, let underlying):
            return "Failed to read task directory '\(path)': \(underlying?.localizedDescription ?? "unknown")"
        case .fileReadFailed(let filename, let underlying):
            return "Failed to read task file '\(filename)': \(underlying?.localizedDescription ?? "unknown")"
        case .yamlParseFailed(let filename, let underlying):
            return "Failed to parse YAML in '\(filename)': \(underlying.localizedDescription)"
        }
    }
}

/// タスク定義 YAML ファイルの読み書きを担当する。
public final class TaskStore: @unchecked Sendable {
    private let directory: URL
    private static let logger = Logger(subsystem: "com.gehnmaisoda.local-runner", category: "TaskStore")

    public init(directory: URL = ConfigPaths.tasksDirectory) {
        self.directory = directory
    }

    /// ディレクトリ内の全タスク定義を読み込む。
    public func loadAll() -> [TaskDefinition] {
        let fm = FileManager.default
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            Self.logger.error("Failed to read task directory '\(self.directory.path)': \(error.localizedDescription)")
            return []
        }
        return files
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let task = loadTask(at: url) else {
                    return nil as TaskDefinition?
                }
                return task
            }
    }

    /// 指定ファイルからタスク定義を読み込む。
    public func loadTask(at url: URL) -> TaskDefinition? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Self.logger.error("Failed to read task file '\(url.lastPathComponent)': \(error.localizedDescription)")
            return nil
        }
        guard let yaml = String(data: data, encoding: .utf8) else {
            Self.logger.error("Failed to decode task file '\(url.lastPathComponent)' as UTF-8")
            return nil
        }
        let decoder = YAMLDecoder()
        let taskId = url.deletingPathExtension().lastPathComponent
        let decoded: TaskDefinition
        do {
            decoded = try decoder.decode(TaskDefinition.self, from: yaml)
        } catch {
            Self.logger.error("Failed to parse YAML in '\(url.lastPathComponent)': \(error.localizedDescription)")
            return nil
        }
        // id をファイル名で上書き（YAML内のidは無視）
        return TaskDefinition(
            id: taskId,
            name: decoded.name,
            description: decoded.description,
            command: decoded.command,
            workingDirectory: decoded.workingDirectory,
            schedule: decoded.schedule,
            enabled: decoded.enabled,
            catchUp: decoded.catchUp,
            slackNotify: decoded.slackNotify,
            slackMentions: decoded.slackMentions,
            timeout: decoded.timeout
        )
    }

    /// タスク定義を YAML ファイルとして保存する。
    public func save(_ task: TaskDefinition) throws {
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        let yaml = try encoder.encode(task)
        let url = directory.appendingPathComponent("\(task.id).yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// タスク定義ファイルを削除する。
    public func delete(_ taskId: String) throws {
        let url = directory.appendingPathComponent("\(taskId).yaml")
        try FileManager.default.removeItem(at: url)
    }

    /// タスク定義ディレクトリの変更日時。ファイル監視に使用。
    public var directoryModificationDate: Date {
        let fm = FileManager.default
        // ディレクトリ自体 + 中のファイルの最新更新日時を取得
        var latest: Date = .distantPast
        if let attrs = try? fm.attributesOfItem(atPath: directory.path),
           let date = attrs[.modificationDate] as? Date {
            latest = date
        }
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for file in files where file.pathExtension == "yaml" || file.pathExtension == "yml" {
                if let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let date = values.contentModificationDate, date > latest {
                    latest = date
                }
            }
        }
        return latest
    }
}
