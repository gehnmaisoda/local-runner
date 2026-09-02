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
      CIRCLEBACK_WEBHOOK_SECRET: "circleback-secret",
    } satisfies Env,
  };
}

async function signature(body: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
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

  test("Circleback signature is required and only minimal metadata is queued", async () => {
    const { env, sent } = mockEnv();
    const payload = JSON.stringify({
      id: "meeting-123", name: "Client meeting", createdAt: "2026-09-02T01:00:00Z",
      icalUid: "calendar-id", notes: "secret notes", transcript: [{ text: "secret transcript" }],
    });
    const response = await worker.fetch(new Request("https://relay.test/webhooks/circleback", {
      method: "POST",
      headers: { "x-signature": await signature(payload, env.CIRCLEBACK_WEBHOOK_SECRET) },
      body: payload,
    }), env);

    expect(response.status).toBe(202);
    const queued = JSON.parse(sent[0]!.body);
    expect(queued.id).toBe("circleback.meeting.completed:meeting-123");
    expect(queued.topic).toBe("circleback.meeting.completed");
    expect(queued.payload.meeting_id).toBe("meeting-123");
    expect(queued.payload.notes).toBeUndefined();
    expect(queued.payload.transcript).toBeUndefined();
  });

  test("invalid Circleback signature is rejected", async () => {
    const { env, sent } = mockEnv();
    const response = await worker.fetch(new Request("https://relay.test/webhooks/circleback", {
      method: "POST", headers: { "x-signature": "wrong" }, body: JSON.stringify({ id: "meeting-123" }),
    }), env);
    expect(response.status).toBe(401);
    expect(sent).toHaveLength(0);
  });
});
