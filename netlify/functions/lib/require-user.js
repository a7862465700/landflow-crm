const { headerValue, jsonResponse } = require("./http");

function bearerToken(event) {
  const raw = headerValue(event, "authorization");
  const match = /^Bearer\s+(\S+)$/i.exec(raw);
  if (!match) return "";
  return match[1];
}

/**
 * Confirm the caller is a signed-in CRM user.
 * The access token is checked with Supabase Auth. A missing project URL or
 * anon key fails closed — the request is rejected and nothing downstream runs.
 */
async function requireSignedInUser(event, deps = {}) {
  const token = bearerToken(event);
  if (!token || token.length < 20) {
    return { ok: false, statusCode: 401, error: "Please sign in again." };
  }

  const url = (process.env.SUPABASE_URL || "").trim().replace(/\/$/, "");
  const anonKey = (process.env.SUPABASE_ANON_KEY || "").trim();
  if (!url || !anonKey) {
    return { ok: false, statusCode: 503, error: "Sign-in check is not configured." };
  }

  const fetchImpl = deps.fetch || fetch;
  let response;
  try {
    response = await fetchImpl(`${url}/auth/v1/user`, {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: anonKey,
      },
    });
  } catch {
    return { ok: false, statusCode: 503, error: "Could not verify sign-in." };
  }

  if (!response.ok) {
    return { ok: false, statusCode: 401, error: "Please sign in again." };
  }

  let user;
  try {
    user = await response.json();
  } catch {
    return { ok: false, statusCode: 401, error: "Please sign in again." };
  }

  if (!user || typeof user.id !== "string" || !user.id) {
    return { ok: false, statusCode: 401, error: "Please sign in again." };
  }

  return { ok: true, user };
}

function authFailure(result) {
  return jsonResponse(result.statusCode, { error: result.error });
}

module.exports = { requireSignedInUser, authFailure, bearerToken };
