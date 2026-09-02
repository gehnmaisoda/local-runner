# LocalRunner Relay

Webhookを受け、1本のCloudflare Queueへ小さなイベントを投入するWorker。AI処理や業務データ本体は扱わない。

## Cloudflare resources

```bash
bun install
bunx wrangler queues create local-runner-events --message-retention-period-secs 1209600
bunx wrangler queues consumer http add local-runner-events --batch-size 1 --message-retries 3 --retry-delay-secs 60 --visibility-timeout-secs 7200
bunx wrangler secret put INGEST_TOKEN
bunx wrangler secret put CIRCLEBACK_WEBHOOK_SECRET
bun run deploy
```

Free planではQueue保持期間が24時間に固定される。Mac停止を最大14日吸収するにはWorkers Paid planを使う。

HTTP Pull用にAccount / Queues / Edit権限のAPI tokenを作り、Mac上の次のファイルへ保存する。tokenをdotfilesへ入れない。

```json
{
  "account_id": "...",
  "queue_id": "...",
  "api_token": "...",
  "poll_interval_seconds": 15,
  "visibility_timeout_seconds": 7200,
  "retry_delay_seconds": 60
}
```

保存先: `~/Library/Application Support/LocalRunner/queue.json`（mode `600`）

Circleback Automationの送信先は `https://<worker>/webhooks/circleback`。Circlebackが表示するsigning secretをWorker secret `CIRCLEBACK_WEBHOOK_SECRET`へ設定する。
