/**
 * PitStop Gemini proxy (Cloudflare Worker).
 *
 * The app calls:   POST https://<worker>/v1beta/models/<model>:generateContent
 *                  header  x-pitstop-token: <APP_TOKEN>
 * The Worker adds the secret GEMINI_API_KEY and forwards the body to Google unchanged.
 *
 * Safety:
 *  - only POST generateContent, only for the models PitStop uses (allowlist below)
 *  - requires the shared APP_TOKEN, so strangers can't spend your quota
 *  - rejects bodies over 100 KB
 *  - forwards nothing about the caller (no IP, no headers) except the request body
 */

// Keep in sync with AIConfig.swift.
const ALLOWED_MODELS = new Set([
  "gemini-3.8-flash",
  "gemini-3.6-flash",
  "gemini-3.5-flash-lite",
  "gemini-3.1-flash-lite",
]);

const MAX_BODY_BYTES = 100_000;
const UPSTREAM = "https://generativelanguage.googleapis.com/v1beta/models";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json(200, { ok: true, models: [...ALLOWED_MODELS], keyConfigured: Boolean(env.GEMINI_API_KEY) });
    }
    if (request.method !== "POST") return json(405, { error: { code: 405, message: "Use POST" } });

    const match = url.pathname.match(/^\/v1beta\/models\/([a-z0-9.\-]+):generateContent$/);
    if (!match || !ALLOWED_MODELS.has(match[1])) {
      return json(404, { error: { code: 404, message: "Unknown endpoint or model" } });
    }
    if (env.APP_TOKEN && request.headers.get("x-pitstop-token") !== env.APP_TOKEN) {
      return json(401, { error: { code: 401, message: "Missing or wrong x-pitstop-token" } });
    }
    if (!env.GEMINI_API_KEY) {
      return json(500, { error: { code: 500, message: "GEMINI_API_KEY secret is not set on the Worker" } });
    }

    const body = await request.text();
    if (body.length > MAX_BODY_BYTES) return json(413, { error: { code: 413, message: "Request too large" } });

    const upstream = await fetch(`${UPSTREAM}/${match[1]}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body,
    });

    // Pass Google's status and body straight through (the app reads 429 retryDelay from it).
    const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
    const retryAfter = upstream.headers.get("Retry-After");
    if (retryAfter) headers["Retry-After"] = retryAfter;
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

function json(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
