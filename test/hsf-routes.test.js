const test = require("node:test");
const assert = require("node:assert/strict");
const { timingSafeEqualString } = require("../netlify/functions/lib/timing-safe-equal");
const { handler: crmSync } = require("../netlify/functions/crm-sync");
const { handler: inviteLender } = require("../netlify/functions/invite-lender");

const USER_TOKEN = "test-user-access-token-xyz";
const SECRET = "test-secret-value-0123456789";
const LOAN_ID = "11111111-1111-4111-8111-111111111111";

const ENV_KEYS = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "HSF_CRM_SYNC_SECRET", "HSF_API_BASE"];

function saveEnv() {
  return Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
}

function restoreEnv(prev) {
  for (const [key, value] of Object.entries(prev)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
}

function useEnv(vars) {
  for (const key of ENV_KEYS) {
    if (vars[key] === undefined) delete process.env[key];
    else process.env[key] = vars[key];
  }
}

function baseEnv(overrides = {}) {
  return {
    SUPABASE_URL: "https://example.supabase.co",
    SUPABASE_ANON_KEY: "test-anon-key",
    HSF_CRM_SYNC_SECRET: SECRET,
    HSF_API_BASE: undefined,
    ...overrides,
  };
}

function mockFetch({ upstreamStatus = 200, upstreamBody = { ok: true }, throwOnUpstream = false } = {}) {
  const calls = [];
  async function fetchImpl(url, opts) {
    const target = String(url);
    calls.push({ url: target, opts });
    if (target.includes("/auth/v1/user")) {
      const header = (opts && opts.headers && opts.headers.Authorization) || "";
      const ok = header === `Bearer ${USER_TOKEN}`;
      return {
        ok,
        status: ok ? 200 : 401,
        json: async () => (ok ? { id: "user-1" } : {}),
        text: async () => "",
      };
    }
    if (target.includes("/rest/v1/loans")) {
      const visible = !target.includes("id=eq.00000000-0000-4000-8000-000000000000");
      const rows = visible ? [{ id: LOAN_ID }] : [];
      return {
        ok: true,
        status: 200,
        json: async () => rows,
        text: async () => JSON.stringify(rows),
      };
    }
    if (throwOnUpstream) throw new Error("upstream failed");
    return {
      ok: upstreamStatus >= 200 && upstreamStatus < 300,
      status: upstreamStatus,
      text: async () => (typeof upstreamBody === "string" ? upstreamBody : JSON.stringify(upstreamBody)),
    };
  }
  return { fetchImpl, calls };
}

async function withFetch(fetchImpl, fn) {
  const previous = global.fetch;
  global.fetch = fetchImpl;
  try {
    return await fn();
  } finally {
    global.fetch = previous;
  }
}

function portalCalls(calls) {
  return calls.filter((call) => call.url.includes("hickorystreetfinance.com"));
}

function signedEvent(body) {
  return {
    httpMethod: "POST",
    headers: { authorization: `Bearer ${USER_TOKEN}` },
    body: JSON.stringify(body),
  };
}

test("constant-time helper matches equal strings and rejects mismatches", () => {
  assert.equal(timingSafeEqualString("same-value", "same-value"), true);
  assert.equal(timingSafeEqualString("same-value", "same-valuE"), false);
  assert.equal(timingSafeEqualString("short", "much-longer-value"), false);
  assert.equal(timingSafeEqualString("", "x"), false);
});

test("crm-sync and invite-lender reject anonymous callers before any outbound call", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv({ HSF_CRM_SYNC_SECRET: undefined }));
    const mocked = mockFetch();
    await withFetch(mocked.fetchImpl, async () => {
      const sync = await crmSync({ httpMethod: "POST", headers: {}, body: "{}" });
      const invite = await inviteLender({ httpMethod: "POST", headers: {}, body: "{}" });
      assert.equal(sync.statusCode, 401);
      assert.equal(invite.statusCode, 401);
      assert.equal(JSON.parse(sync.body).error, "Please sign in again.");
    });
    assert.equal(mocked.calls.length, 0);
  } finally {
    restoreEnv(prev);
  }
});

test("a signed-in caller is still rejected when the shared secret is missing", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv({ HSF_CRM_SYNC_SECRET: undefined }));
    const mocked = mockFetch();
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
    );
    assert.equal(response.statusCode, 503);
    assert.equal(JSON.parse(response.body).error, "HSF sync is not configured.");
    assert.equal(portalCalls(mocked.calls).length, 0);
    assert.equal(response.body.includes("Bearer"), false);
  } finally {
    restoreEnv(prev);
  }
});

test("placeholder and short secrets fail closed", async () => {
  const prev = saveEnv();
  try {
    for (const secret of ["replace-with-a-new-long-random-value", "too-short"]) {
      useEnv(baseEnv({ HSF_CRM_SYNC_SECRET: secret }));
      const mocked = mockFetch();
      const response = await withFetch(mocked.fetchImpl, () =>
        crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
      );
      assert.equal(response.statusCode, 503);
      assert.equal(portalCalls(mocked.calls).length, 0);
    }
  } finally {
    restoreEnv(prev);
  }
});

test("a bad HSF host is rejected and the secret is not sent there", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv({ HSF_API_BASE: "https://evil.example/steal" }));
    const mocked = mockFetch();
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
    );
    assert.equal(response.statusCode, 503);
    assert.equal(portalCalls(mocked.calls).length, 0);
    assert.equal(mocked.calls.some((call) => call.url.includes("evil.example")), false);
  } finally {
    restoreEnv(prev);
  }
});

test("crm-sync forwards only the loan id and the server-side secret", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv());
    const mocked = mockFetch({ upstreamBody: { success: true } });
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID, drop: "this", authorization: SECRET }))
    );
    assert.equal(response.statusCode, 200);
    const outbound = portalCalls(mocked.calls);
    assert.equal(outbound.length, 1);
    assert.equal(outbound[0].url, "https://hickorystreetfinance.com/api/crm-sync");
    assert.equal(outbound[0].opts.headers.Authorization, `Bearer ${SECRET}`);
    assert.equal(outbound[0].opts.redirect, "error");
    assert.deepEqual(JSON.parse(outbound[0].opts.body), { crm_loan_id: LOAN_ID });
    assert.equal(JSON.parse(response.body).success, true);
    const authCall = mocked.calls.find((call) => call.url.includes("/auth/v1/user"));
    assert.equal(authCall.opts.headers.Authorization, `Bearer ${USER_TOKEN}`);
    assert.equal(authCall.opts.headers.apikey, "test-anon-key");
  } finally {
    restoreEnv(prev);
  }
});

test("invite-lender normalizes the email and does not forward extra fields", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv());
    const mocked = mockFetch({ upstreamStatus: 200, upstreamBody: { message: "Invite sent" } });
    const response = await withFetch(mocked.fetchImpl, () =>
      inviteLender(
        signedEvent({
          email: " Mailto:Buyer@Example.com ",
          name: "Ada",
          businessName: "Ada LLC",
          role: "admin",
        })
      )
    );
    assert.equal(response.statusCode, 200);
    const outbound = portalCalls(mocked.calls);
    assert.equal(outbound.length, 1);
    assert.equal(outbound[0].url, "https://hickorystreetfinance.com/api/admin/invite-lender");
    assert.deepEqual(JSON.parse(outbound[0].opts.body), {
      email: "buyer@example.com",
      name: "Ada",
      businessName: "Ada LLC",
    });
    assert.equal(outbound[0].opts.headers.Authorization, `Bearer ${SECRET}`);
  } finally {
    restoreEnv(prev);
  }
});

test("an upstream body that echoes the secret is scrubbed", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv());
    const mocked = mockFetch({
      upstreamStatus: 500,
      upstreamBody: { error: `portal said ${SECRET}` },
    });
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
    );
    assert.equal(response.statusCode, 500);
    assert.equal(response.body.includes(SECRET), false);
    assert.equal(JSON.parse(response.body).error, "portal said [redacted]");
  } finally {
    restoreEnv(prev);
  }
});

test("non-JSON upstream responses do not pass through", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv());
    const mocked = mockFetch({ upstreamStatus: 502, upstreamBody: `<html>${SECRET}</html>` });
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
    );
    assert.equal(response.statusCode, 502);
    assert.equal(response.body.includes(SECRET), false);
    assert.equal(JSON.parse(response.body).error, "Hickory Street Finance returned an unexpected response.");
  } finally {
    restoreEnv(prev);
  }
});

test("unreachable portal and invalid input are rejected", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv());
    const down = mockFetch({ throwOnUpstream: true });
    const failed = await withFetch(down.fetchImpl, () => crmSync(signedEvent({ crm_loan_id: LOAN_ID })));
    assert.equal(failed.statusCode, 502);

    const badId = mockFetch();
    const invalid = await withFetch(badId.fetchImpl, () => crmSync(signedEvent({ crm_loan_id: "not-a-loan" })));
    assert.equal(invalid.statusCode, 400);
    assert.equal(portalCalls(badId.calls).length, 0);

    const hidden = mockFetch();
    const missing = await withFetch(hidden.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: "00000000-0000-4000-8000-000000000000" }))
    );
    assert.equal(missing.statusCode, 404);
    assert.equal(portalCalls(hidden.calls).length, 0);

    const badEmail = mockFetch();
    const invite = await withFetch(badEmail.fetchImpl, () => inviteLender(signedEvent({ email: "nope" })));
    assert.equal(invite.statusCode, 400);
    assert.equal(portalCalls(badEmail.calls).length, 0);

    const get = await crmSync({ httpMethod: "GET", headers: {} });
    assert.equal(get.statusCode, 405);
  } finally {
    restoreEnv(prev);
  }
});

test("sign-in cannot be checked when Supabase env is missing", async () => {
  const prev = saveEnv();
  try {
    useEnv(baseEnv({ SUPABASE_URL: undefined, SUPABASE_ANON_KEY: undefined }));
    const mocked = mockFetch();
    const response = await withFetch(mocked.fetchImpl, () =>
      crmSync(signedEvent({ crm_loan_id: LOAN_ID }))
    );
    assert.equal(response.statusCode, 503);
    assert.equal(JSON.parse(response.body).error, "Sign-in check is not configured.");
    assert.equal(mocked.calls.length, 0);
  } finally {
    restoreEnv(prev);
  }
});
