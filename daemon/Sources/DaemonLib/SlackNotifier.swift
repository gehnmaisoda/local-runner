import Foundation
import Core

/// Slack Webhook を使って通知を送信する。
public final class SlackNotifier: @unchecked Sendable {
    public var webhookURL: String?

    /// タスク失敗を Slack に通知する。
    /// Slack mrkdwn の特殊文字をエスケープする。
    private func escapeSlack(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
    }

    public func notifyFailure(task: TaskDefinition, record: ExecutionRecord) {
        guard let urlString = webhookURL, let url = URL(string: urlString) else { return }

        let stderrPreview = String(record.stderr.prefix(500))
        let header = record.status == .timeout
            ? ":alarm_clock: *タスクタイムアウト: \(escapeSlack(task.name))*"
            : ":x: *タスク実行失敗: \(escapeSlack(task.name))*"
        let text = [
            header,
            "• コマンド: `\(escapeSlack(task.command))`",
            "• 終了コード: \(record.exitCode ?? -1)",
            "• 時刻: \(Log.formatDate(record.startedAt))",
            "• 実行時間: \(record.durationText)",
        ].joined(separator: "\n")

        let payload: [String: Any] = [
            "text": text,
            "blocks": [
                [
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": text]
                ],
                [
                    "type": "section",
                    "text": ["type": "mrkdwn", "text": "```\n\(escapeSlack(stderrPreview))\n```"]
                ]
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                Log.info("Slack", "送信失敗: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                Log.info("Slack", "予期しないステータス: \(http.statusCode)")
            }
        }.resume()
    }

}
