import Foundation
import Core

/// Slack Bot Token + chat.postMessage API を使って通知を送信する。
public final class SlackNotifier: @unchecked Sendable {
    public var botToken: String?
    public var channel: String?

    private static let apiURL = URL(string: "https://slack.com/api/chat.postMessage")!

    /// Slack API エラーコードに対するヒントを返す。
    static func errorHint(_ code: String) -> String {
        switch code {
        case "not_in_channel": return " — Bot がチャンネルに参加していません。/invite @Bot名 を実行してください"
        case "channel_not_found": return " — チャンネルが見つかりません"
        case "invalid_auth": return " — Bot Token が無効です"
        case "token_revoked": return " — Bot Token が無効化されています"
        default: return ""
        }
    }

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

    /// Slack section block の text 上限（3000文字）からマークダウン装飾分を差し引いた安全な上限。
    private static let logPreviewLimit = 2800

    /// スレッドに実行ログを追記する。stdout / stderr を別々の block に分けて投稿。
    private func postLogToThread(token: String, channel: String, threadTs: String, record: ExecutionRecord) {
        let stdoutPreview = String(record.stdout.prefix(Self.logPreviewLimit))
        let stderrPreview = String(record.stderr.prefix(Self.logPreviewLimit))

        var blocks: [[String: Any]] = []
        var textParts: [String] = []

        if !stdoutPreview.isEmpty {
            let text = "*stdout:*\n```\n\(Self.escapeSlack(stdoutPreview))\n```"
            blocks.append(["type": "section", "text": ["type": "mrkdwn", "text": text]])
            textParts.append(text)
        }
        if !stderrPreview.isEmpty {
            let text = "*stderr:*\n```\n\(Self.escapeSlack(stderrPreview))\n```"
            blocks.append(["type": "section", "text": ["type": "mrkdwn", "text": text]])
            textParts.append(text)
        }
        if blocks.isEmpty {
            let text = "_(出力なし)_"
            blocks.append(["type": "section", "text": ["type": "mrkdwn", "text": text]])
            textParts.append(text)
        }

        let payload: [String: Any] = [
            "channel": channel,
            "thread_ts": threadTs,
            "text": textParts.joined(separator: "\n"),
            "blocks": blocks,
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
                    let errCode = json["error"] as? String ?? "unknown"
                    let hint = Self.errorHint(errCode)
                    Log.info("Slack", "API エラー: \(errCode)\(hint)")
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
