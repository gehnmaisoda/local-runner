export interface Env {
  EVENT_QUEUE: Queue<string>;
  INGEST_TOKEN: string;
}

export interface EventEnvelope {
  version: 1;
  id: string;
  topic: string;
  occurred_at: string;
  payload: Record<string, unknown>;
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }
    if (request.method === "POST" && url.pathname === "/events") {
      return handleGenericEvent(request, env);
    }
    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;
