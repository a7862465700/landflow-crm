// Scheduled health check for the deed-extraction models.
//
// Deed imports broke on 2026-06-15 when a pinned model reached its retirement
// date, and nobody found out for five weeks. This runs daily and reports the
// moment a configured model stops resolving.
//
// It checks *every* model in the chain rather than just extracting a sample
// deed. That distinction matters: once the fallback in deed-extraction.js is in
// place, a dead primary still produces successful imports, so an end-to-end
// extraction test would stay green while the chain quietly burned down to its
// last model. Availability checks surface that degradation. They also cost zero
// tokens and need no deed committed to the repo.
//
// Schedule is configured in netlify.toml.

const Anthropic = require("@anthropic-ai/sdk");
const { MODELS } = require("./lib/deed-extraction");

async function checkModel(client, model) {
  try {
    await client.models.retrieve(model);
    return { model, ok: true };
  } catch (err) {
    if (err.status === 404) {
      return { model, ok: false, reason: "retired or unrecognized (404)" };
    }
    return { model, ok: false, reason: `${err.status || "network"}: ${err.message}` };
  }
}

async function sendAlert(subject, body) {
  const { RESEND_API_KEY, ALERT_EMAIL_TO, ALERT_EMAIL_FROM } = process.env;

  if (!RESEND_API_KEY || !ALERT_EMAIL_TO || !ALERT_EMAIL_FROM) {
    console.error("[canary] email not configured (need RESEND_API_KEY, ALERT_EMAIL_TO, ALERT_EMAIL_FROM) — alert logged only");
    return false;
  }

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: ALERT_EMAIL_FROM, to: [ALERT_EMAIL_TO], subject, text: body }),
  });

  if (!resp.ok) {
    console.error(`[canary] Resend rejected the alert: ${resp.status} ${await resp.text()}`);
    return false;
  }
  return true;
}

exports.handler = async () => {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error("[canary] ANTHROPIC_API_KEY not configured");
    return { statusCode: 500, body: "ANTHROPIC_API_KEY not configured" };
  }

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const results = await Promise.all(MODELS.map((m) => checkModel(client, m)));

  const healthy = results.filter((r) => r.ok).map((r) => r.model);
  const broken = results.filter((r) => !r.ok);
  const primaryOk = results[0].ok;

  if (!broken.length) {
    console.log(`[canary] OK — all extraction models available: ${healthy.join(", ")}`);
    return { statusCode: 200, body: `OK: ${healthy.join(", ")}` };
  }

  const critical = healthy.length === 0;
  const severity = critical ? "CRITICAL" : primaryOk ? "WARNING" : "DEGRADED";

  const summary =
    `LandFlow deed extraction — model health ${severity}\n\n` +
    broken.map((r) => `  UNAVAILABLE  ${r.model} — ${r.reason}`).join("\n") +
    (healthy.length ? `\n` + healthy.map((m) => `  OK           ${m}`).join("\n") : "") +
    `\n\n` +
    (critical
      ? "No extraction model is available. Deed PDF import is DOWN.\n" +
        "Fix: set ANTHROPIC_MODELS in Netlify to a current model, then redeploy."
      : primaryOk
        ? "Imports are working on the primary model. A fallback entry is stale and\n" +
          "should be replaced so the safety net is intact."
        : "Imports still work, but they are running on a fallback model. The primary\n" +
          "is gone. Replace it in ANTHROPIC_MODELS before the fallback retires too.") +
    `\n\nConfigured chain: ${MODELS.join(" -> ")}\n`;

  console.error(`[canary] ${summary}`);
  await sendAlert(`LandFlow: deed extraction model ${severity}`, summary);

  // Non-2xx so the run shows as failed in the Netlify functions log even if
  // email delivery is not configured yet.
  return { statusCode: critical ? 500 : 207, body: summary };
};
