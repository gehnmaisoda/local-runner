export interface Env {
  EVENT_QUEUE: Queue<string>;
  INGEST_TOKEN: string;
  CIRCLEBACK_WEBHOOK_SECRET: string;
}

export interface EventEnvelope {
  version: 1;
  id: string;
  topic: string;
  occurred_at: string;
  payload: Record<string, unknown>;
}

interface CirclebackPayload {
  id?: unknown;
  name?: unknown;
  createdAt?: unknown;
  icalUid?: unknown;
}

const json = (value: unknown, status = 200): Response => Response.json(value, { status });

function isEnvelope(value: unknown): value is EventEnvelope {
  if (!value || typeof value !== "object") return false;
  const event = value as Record<string, unknown>;
  return event.version === 1
    && typeof event.id === "string" && event.id.length > 0
    && typeof event.topic === "string" && event.topic.length > 0
    && typeof event.occurred_at === "string"
    && !!event.payload && typeof event.payload === "object" && !Array.isArray(event.payload);
}

function authorized(request: Request, token: string | undefined): boolean {
  if (!token) return false;
  return request.headers.get("authorization") === `Bearer ${token}`;
}

function hex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function verifyCirclebackSignature(
  body: ArrayBuffer,
  providedSignature: string | null,
  secret: string | undefined,
): Promise<boolean> {
  if (!providedSignature || !secret) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expected = hex(await crypto.subtle.sign("HMAC", key, body));
  return constantTimeEqual(expected, providedSignature.toLowerCase());
}

async function enqueue(env: Env, event: EventEnvelope): Promise<void> {
  // text に固定すると HTTP Pull consumer 側でbase64 decodeが不要。
  await env.EVENT_QUEUE.send(JSON.stringify(event), { contentType: "text" });
}

async function handleGenericEvent(request: Request, env: Env): Promise<Response> {
  if (!authorized(request, env.INGEST_TOKEN)) return json({ error: "unauthorized" }, 401);

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (!isEnvelope(body)) return json({ error: "invalid_event_envelope" }, 400);

  await enqueue(env, body);
  return json({ accepted: true, id: body.id }, 202);
}

async function handleCircleback(request: Request, env: Env): Promise<Response> {
  const rawBody = await request.arrayBuffer();
  const valid = await verifyCirclebackSignature(
    rawBody,
    request.headers.get("x-signature"),
    env.CIRCLEBACK_WEBHOOK_SECRET,
  );
  if (!valid) return json({ error: "invalid_signature" }, 401);

  let payload: CirclebackPayload;
  try {
    payload = JSON.parse(new TextDecoder().decode(rawBody)) as CirclebackPayload;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof payload.id !== "string" || payload.id.length === 0) {
    return json({ error: "missing_meeting_id" }, 400);
  }

  const createdAt = typeof payload.createdAt === "string"
    ? payload.createdAt
    : new Date().toISOString();
  const event: EventEnvelope = {
    version: 1,
    id: `circleback.meeting.completed:${payload.id}`,
    topic: "circleback.meeting.completed",
    occurred_at: createdAt,
    payload: {
      meeting_id: payload.id,
      name: typeof payload.name === "string" ? payload.name : null,
      created_at: typeof payload.createdAt === "string" ? payload.createdAt : null,
      ical_uid: typeof payload.icalUid === "string" ? payload.icalUid : null,
    },
  };

  await enqueue(env, event);
  return json({ accepted: true, id: event.id }, 202);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (request.method === "POST" && url.pathname === "/events") {
      return handleGenericEvent(request, env);
    }
    if (request.method === "POST" && url.pathname === "/webhooks/circleback") {
      return handleCircleback(request, env);
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;
