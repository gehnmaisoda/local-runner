import Foundation
import Core

/// 設定から Slack Bot Token を決める。
///
/// `slack_bot_token` に直接書かれていればそれを使い、空なら `slack_bot_token_command` を実行して
/// 標準出力を使う。コマンドを使うと、トークンを設定ファイルに平文で置かずに済む。
public enum SlackTokenResolver {
    /// コマンドの実行を待つ上限（秒）。応答しないコマンドで通知処理を止め続けない。
    public static let commandTimeout: TimeInterval = 20

    /// 直接指定かコマンドのどちらかが設定されているか。
    public static func isConfigured(token: String?, command: String?) -> Bool {
        normalized(token) != nil || normalized(command) != nil
    }

    /// Bot Token を返す。取得できなければ nil。
    public static func resolve(
        token: String?,
        command: String?,
        runner: (String) -> String? = { runCommand($0) }
    ) -> String? {
        if let token = normalized(token) { return token }
        guard let command = normalized(command) else { return nil }
        return normalized(runner(command))
    }

    /// コマンドをログインシェルで実行し、標準出力を返す。失敗・タイムアウト時は nil。
    /// 標準出力はトークンなのでログに出さない。
    public static func runCommand(_ command: String, timeout: TimeInterval = commandTimeout) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.environment = TaskExecutor.complementedEnvironment(ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            Log.info("Slack", "トークン取得コマンドを起動できません: \(error.localizedDescription)")
            return nil
        }

        // トークンは短いのでパイプが詰まることはなく、終了を待ってからまとめて読めばよい
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            Log.info("Slack", "トークン取得コマンドが \(Int(timeout)) 秒以内に終わりませんでした")
            return nil
        }
        guard process.terminationStatus == 0 else {
            Log.info("Slack", "トークン取得コマンドが終了コード \(process.terminationStatus) で失敗しました")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
