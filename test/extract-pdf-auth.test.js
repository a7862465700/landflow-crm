const test = require("node:test");
const assert = require("node:assert/strict");

const USER_TOKEN = "test-user-access-token-xyz";
let handler;

test("extract-pdf module loads", () => {
  ({ handler } = require("../netlify/functions/extract-pdf"));
  assert.equal(typeof handler, "function");
});

test("extract-pdf rejects anonymous callers before reading the request body", async () => {
  const previous = global.fetch;
  let called = false;
  global.fetch = async () => {
    called = true;
    throw new Error("fetch should not run");
  };
  const prevKey = process.env.ANTHROPIC_API_KEY;
  process.env.ANTHROPIC_API_KEY = "test-anthropic-key";
  try {
    const response = await handler({
      httpMethod: "POST",
      headers: {},
      body: JSON.stringify({ pdf_base64: "abc" }),
    });
    assert.equal(response.statusCode, 401);
    assert.equal(JSON.parse(response.body).error, "Please sign in again.");
    assert.equal(called, false);
    assert.equal(response.headers["Access-Control-Allow-Origin"], undefined);
  } finally {
    global.fetch = previous;
    if (prevKey === undefined) delete process.env.ANTHROPIC_API_KEY;
    else process.env.ANTHROPIC_API_KEY = prevKey;
  }
});

test("extract-pdf fails closed when sign-in cannot be checked", async () => {
  const previousUrl = process.env.SUPABASE_URL;
  const previousKey = process.env.SUPABASE_ANON_KEY;
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_ANON_KEY;
  const previousFetch = global.fetch;
  let called = false;
  global.fetch = async () => {
    called = true;
    return { ok: true, json: async () => ({ id: "user-1" }) };
  };
  try {
    const response = await handler({
      httpMethod: "POST",
      headers: { Authorization: `Bearer ${USER_TOKEN}` },
      body: JSON.stringify({ pdf_base64: "abc" }),
    });
    assert.equal(response.statusCode, 503);
    assert.equal(JSON.parse(response.body).error, "Sign-in check is not configured.");
    assert.equal(called, false);
  } finally {
    global.fetch = previousFetch;
    if (previousUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = previousUrl;
    if (previousKey === undefined) delete process.env.SUPABASE_ANON_KEY;
    else process.env.SUPABASE_ANON_KEY = previousKey;
  }
});

test("extract-pdf checks the caller with Supabase before extraction", async () => {
  process.env.SUPABASE_URL = "https://example.supabase.co";
  process.env.SUPABASE_ANON_KEY = "test-anon-key";
  delete process.env.ANTHROPIC_API_KEY;
  const previousFetch = global.fetch;
  const calls = [];
  global.fetch = async (url, opts) => {
    calls.push({ url: String(url), opts });
    return { ok: true, status: 200, json: async () => ({ id: "user-1" }), text: async () => "" };
  };
  try {
    const response = await handler({
      httpMethod: "POST",
      headers: { Authorization: `Bearer ${USER_TOKEN}` },
      body: JSON.stringify({}),
    });
    assert.equal(response.statusCode, 400);
    assert.equal(JSON.parse(response.body).error, "pdf_base64 is required");
    assert.equal(calls.length, 1);
    assert.match(calls[0].url, /\/auth\/v1\/user$/);
    assert.equal(calls[0].opts.headers.Authorization, `Bearer ${USER_TOKEN}`);
  } finally {
    global.fetch = previousFetch;
    delete process.env.SUPABASE_URL;
    delete process.env.SUPABASE_ANON_KEY;
  }
});
