import Foundation
import Yams

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
    public var notifyOnFailure: Bool

    public init(
        id: String,
        name: String,
        description: String? = nil,
        command: String,
        workingDirectory: String? = nil,
        schedule: Schedule = .daily(),
        enabled: Bool = true,
        catchUp: Bool = true,
        notifyOnFailure: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.workingDirectory = workingDirectory
        self.schedule = schedule
        self.enabled = enabled
        self.catchUp = catchUp
        self.notifyOnFailure = notifyOnFailure
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, command
        case workingDirectory = "working_directory"
        case schedule, enabled
        case catchUp = "catch_up"
        case notifyOnFailure = "notify_on_failure"
    }
}

// MARK: - TaskStore

/// タスク定義 YAML ファイルの読み書きを担当する。
public final class TaskStore: @unchecked Sendable {
    private let directory: URL

    public init(directory: URL = ConfigPaths.tasksDirectory) {
        self.directory = directory
    }

    /// ディレクトリ内の全タスク定義を読み込む。
    public func loadAll() -> [TaskDefinition] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            print("[TaskStore] ディレクトリの読み込みに失敗: \(directory.path)")
            return []
        }
        return files
            .filter { $0.pathExtension == "yaml" || $0.pathExtension == "yml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let task = loadTask(at: url) else {
                    print("[TaskStore] パース失敗: \(url.lastPathComponent)")
                    return nil as TaskDefinition?
                }
                return task
            }
    }

    /// 指定ファイルからタスク定義を読み込む。
    public func loadTask(at url: URL) -> TaskDefinition? {
        guard let data = try? Data(contentsOf: url),
              let yaml = String(data: data, encoding: .utf8) else { return nil }
        let decoder = YAMLDecoder()
        let taskId = url.deletingPathExtension().lastPathComponent
        guard let decoded = try? decoder.decode(TaskDefinition.self, from: yaml) else { return nil }
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
            notifyOnFailure: decoded.notifyOnFailure
        )
    }

    /// タスク定義を YAML ファイルとして保存する。
    public func save(_ task: TaskDefinition) throws {
        let encoder = YAMLEncoder()
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
