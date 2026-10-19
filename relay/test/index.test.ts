import { describe, expect, test } from "bun:test";
import worker, { type Env } from "../src/index";

function mockEnv() {
  const sent: Array<{ body: string; options?: QueueSendOptions }> = [];
  const queue = {
    async send(body: string, options?: QueueSendOptions) {
      sent.push({ body, options });
      return { metadata: { metrics: { backlogCount: 0, backlogBytes: 0, oldestMessageTimestamp: 0 } } };
    },
  } as unknown as Queue<string>;
  return {
    sent,
    env: {
      EVENT_QUEUE: queue,
      INGEST_TOKEN: "ingest-secret",
    } satisfies Env,
  };
}

describe("relay", () => {
  test("health", async () => {
    const { env } = mockEnv();
    const response = await worker.fetch(new Request("https://relay.test/health"), env);
    expect(response.status).toBe(200);
  });

  test("generic events require bearer auth and enqueue text", async () => {
    const { env, sent } = mockEnv();
    const event = {
      version: 1, id: "demo:1", topic: "demo.completed",
      occurred_at: "2026-09-02T00:00:00Z", payload: { value: 1 },
    };
    const response = await worker.fetch(new Request("https://relay.test/events", {
      method: "POST",
      headers: { authorization: "Bearer ingest-secret", "content-type": "application/json" },
      body: JSON.stringify(event),
    }), env);

    expect(response.status).toBe(202);
    expect(sent).toHaveLength(1);
    expect(JSON.parse(sent[0]!.body)).toEqual(event);
    expect(sent[0]!.options?.contentType).toBe("text");
  });
});
