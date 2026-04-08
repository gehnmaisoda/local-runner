import Foundation
import Core

/// Slack Bot Token + chat.postMessage API を使って通知を送信する。
public final class SlackNotifier: @unchecked Sendable {
    public var botToken: String?
    public var channel: String?

    private static let apiURL = URL(string: "https://slack.com/api/chat.postMessage")!

    /// Slack mrkdwn の特殊文字をエスケープする。
    static func escapeSlack(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// タスク完了を Slack に通知し、スレッドに実行ログを追記する。
    public func notifyCompletion(task: TaskDefinition, record: ExecutionRecord) {
        guard let token = botToken, !token.isEmpty,
              let channel = channel, !channel.isEmpty else { return }

        let emoji = record.status == .success ? ":white_check_mark:" : record.status == .timeout ? ":alarm_clock:" : ":x:"
        let statusText = record.status == .success ? "成功" : record.status == .timeout ? "タイムアウト" : "失敗"

        // メンション文字列を組み立て
        let mentionLine: String
        if let mentions = task.slackMentions, !mentions.isEmpty {
            mentionLine = mentions.joined(separator: " ") + "\n"
        } else {
            mentionLine = ""
        }

        let header = "\(emoji) *タスク\(statusText): \(Self.escapeSlack(task.name))*"
        let details = [
            "• コマンド: `\(Self.escapeSlack(task.command))`",
            "• 終了コード: \(record.exitCode ?? -1)",
            "• 時刻: \(Log.formatDate(record.startedAt))",
            "• 実行時間: \(record.durationText)",
        ].joined(separator: "\n")

        let text = mentionLine + header + "\n" + details

        let payload: [String: Any] = [
            "channel": channel,
            "text": text,
            "blocks": [
                [
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": text]
                ],
            ],
        ]

        postMessage(token: token, payload: payload) { [weak self] threadTs in
            guard let self, let threadTs else { return }
            self.postLogToThread(token: token, channel: channel, threadTs: threadTs, record: record)
        }
    }

    /// スレッドに実行ログを追記する。
    private func postLogToThread(token: String, channel: String, threadTs: String, record: ExecutionRecord) {
        // Slack section block の text は最大3000文字。余裕を見て各1200文字に制限。
        let stdoutPreview = String(record.stdout.prefix(1200))
        let stderrPreview = String(record.stderr.prefix(1200))

        var logParts: [String] = []
        if !stdoutPreview.isEmpty {
            logParts.append("*stdout:*\n```\n\(Self.escapeSlack(stdoutPreview))\n```")
        }
        if !stderrPreview.isEmpty {
            logParts.append("*stderr:*\n```\n\(Self.escapeSlack(stderrPreview))\n```")
        }
        if logParts.isEmpty {
            logParts.append("_(出力なし)_")
        }

        let logText = logParts.joined(separator: "\n")

        let payload: [String: Any] = [
            "channel": channel,
            "thread_ts": threadTs,
            "text": logText,
            "blocks": [
                [
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": logText]
                ],
            ],
        ]

        postMessage(token: token, payload: payload)
    }

    /// chat.postMessage を送信する。completion で thread_ts を返す。
    private func postMessage(token: String, payload: [String: Any], completion: ((String?) -> Void)? = nil) {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion?(nil)
            return
        }

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                Log.info("Slack", "送信失敗: \(error.localizedDescription)")
                completion?(nil)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion?(nil)
                return
            }
            if http.statusCode != 200 {
                Log.info("Slack", "予期しないステータス: \(http.statusCode)")
                completion?(nil)
                return
            }

            // thread_ts を取得
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = json["ok"] as? Bool {
                if !ok {
                    let errMsg = json["error"] as? String ?? "unknown"
                    Log.info("Slack", "API エラー: \(errMsg)")
                    completion?(nil)
                } else {
                    let ts = json["ts"] as? String
                    completion?(ts)
                }
            } else {
                completion?(nil)
            }
        }.resume()
    }
}
