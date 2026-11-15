const { requireSignedInUser, authFailure } = require("./require-user");
const { jsonResponse, rawBody } = require("./http");
const { timingSafeEqualString } = require("./timing-safe-equal");

const HSF_HOST = "hickorystreetfinance.com";
const MIN_SECRET_LENGTH = 16;
const PLACEHOLDERS = [
  "changeme",
  "your-secret",
  "replace-me",
  "secret",
  "password",
  "replace-with-a-new-long-random-value",
];

/**
 * The shared secret is read from the environment and attached only on the
 * server-to-server call to Hickory Street Finance. Callers of this function
 * never send it. A missing, short, or placeholder value rejects the request.
 */
function configuredSecret() {
  const raw = process.env.HSF_CRM_SYNC_SECRET;
  if (typeof raw !== "string") return null;
  const secret = raw.trim();
  if (!secret) return null;
  const lower = secret.toLowerCase();
  for (const placeholder of PLACEHOLDERS) {
    if (timingSafeEqualString(lower, placeholder)) return null;
  }
  if (secret.length < MIN_SECRET_LENGTH) return null;
  return secret;
}

function hsfOrigin() {
  const raw = (process.env.HSF_API_BASE || `https://${HSF_HOST}`).trim();
  let url;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.hostname !== HSF_HOST) return null;
  if (url.username || url.password) return null;
  return url.origin;
}

function scrub(value, secret) {
  if (typeof value === "string") {
    return secret && value.includes(secret) ? value.split(secret).join("[redacted]") : value;
  }
  if (Array.isArray(value)) return value.map((item) => scrub(item, secret));
  if (value && typeof value === "object") {
    const out = {};
    for (const [key, item] of Object.entries(value)) out[key] = scrub(item, secret);
    return out;
  }
  return value;
}

async function forwardToHsf({ event, upstreamPath, buildBody, authorize, fetchImpl }) {
  const method = event && event.httpMethod;
  if (method === "OPTIONS") {
    return { statusCode: 204, headers: { "Cache-Control": "no-store" }, body: "" };
  }
  if (method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const fetchFn = fetchImpl || fetch;
  const authResult = await requireSignedInUser(event, { fetch: fetchFn });
  if (!authResult.ok) return authFailure(authResult);

  const secret = configuredSecret();
  const origin = hsfOrigin();
  if (!secret || !origin) {
    return jsonResponse(503, { error: "HSF sync is not configured." });
  }

  const raw = rawBody(event);
  if (raw.length > 20000) {
    return jsonResponse(413, { error: "Request is too large." });
  }

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    return jsonResponse(400, { error: "Expected JSON." });
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return jsonResponse(400, { error: "Expected JSON." });
  }

  const built = buildBody(payload);
  if (!built || built.error) {
    return jsonResponse(400, { error: (built && built.error) || "Invalid request." });
  }

  if (typeof authorize === "function") {
    let decision;
    try {
      decision = await authorize({ user: authResult.user, body: built.body, event, fetchImpl: fetchFn });
    } catch {
      return jsonResponse(503, { error: "Could not confirm this request." });
    }
    if (!decision || !decision.ok) {
      return jsonResponse((decision && decision.statusCode) || 403, {
        error: (decision && decision.error) || "Not allowed.",
      });
    }
  }

  let upstream;
  try {
    upstream = await fetchFn(`${origin}${upstreamPath}`, {
      method: "POST",
      redirect: "error",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${secret}`,
      },
      body: JSON.stringify(built.body),
    });
  } catch {
    return jsonResponse(502, { error: "Could not reach Hickory Street Finance." });
  }

  let text = "";
  try {
    text = await upstream.text();
  } catch {
    return jsonResponse(502, { error: "Could not reach Hickory Street Finance." });
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = null;
  }
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    const status = upstream.status >= 400 && upstream.status <= 599 ? upstream.status : 502;
    return jsonResponse(status, { error: "Hickory Street Finance returned an unexpected response." });
  }

  return jsonResponse(upstream.status || 502, scrub(data, secret));
}

module.exports = { forwardToHsf, configuredSecret, hsfOrigin };
