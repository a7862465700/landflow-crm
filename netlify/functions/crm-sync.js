const { forwardToHsf } = require("./lib/hsf-forward");
const { bearerToken } = require("./lib/require-user");

const LOAN_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The signed-in user must be able to read this loan (Supabase row security)
// before we ask Hickory Street Finance to sync it.
async function confirmLoanVisible({ event, body, fetchImpl }) {
  const url = (process.env.SUPABASE_URL || "").trim().replace(/\/$/, "");
  const anonKey = (process.env.SUPABASE_ANON_KEY || "").trim();
  const token = bearerToken(event);
  if (!url || !anonKey || !token) {
    return { ok: false, statusCode: 503, error: "Could not confirm this loan." };
  }

  const response = await fetchImpl(
    `${url}/rest/v1/loans?id=eq.${encodeURIComponent(body.crm_loan_id)}&select=id`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        apikey: anonKey,
        Accept: "application/json",
      },
    }
  );
  if (!response.ok) {
    return { ok: false, statusCode: 503, error: "Could not confirm this loan." };
  }

  let rows;
  try {
    rows = await response.json();
  } catch {
    return { ok: false, statusCode: 503, error: "Could not confirm this loan." };
  }
  if (!Array.isArray(rows) || rows.length !== 1) {
    return { ok: false, statusCode: 404, error: "Loan not found." };
  }
  return { ok: true };
}

// Signed-in CRM users can ask LandFlow to sync one loan they can see.
// The shared secret Hickory Street Finance expects is added here, from the environment.
exports.handler = (event) =>
  forwardToHsf({
    event,
    upstreamPath: "/api/crm-sync",
    authorize: confirmLoanVisible,
    buildBody(payload) {
      const id = payload.crm_loan_id;
      if (typeof id !== "string" || !LOAN_ID.test(id)) {
        return { error: "A loan id is required." };
      }
      return { body: { crm_loan_id: id } };
    },
  });
