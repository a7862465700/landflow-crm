const Anthropic = require("@anthropic-ai/sdk");
const { extractDeed, validateDeed } = require("./lib/deed-extraction");

/**
 * Translate a failure into a status code and a message that says what to do
 * about it. The frontend surfaces `error` directly in a toast, so this text is
 * what the operator reads.
 */
function describeFailure(err) {
  if (err.status === 503) {
    return { statusCode: 503, error: err.message };
  }
  if (err instanceof Anthropic.AuthenticationError) {
    return { statusCode: 500, error: "Anthropic API key is invalid or expired — update ANTHROPIC_API_KEY in Netlify." };
  }
  if (err instanceof Anthropic.PermissionDeniedError) {
    return { statusCode: 500, error: "Anthropic API key lacks access to the extraction model — check the key's workspace permissions." };
  }
  if (err instanceof Anthropic.RateLimitError) {
    return { statusCode: 429, error: "Anthropic rate limit hit. Wait a moment and try this deed again." };
  }
  if (err instanceof Anthropic.BadRequestError) {
    return { statusCode: 400, error: `The PDF was rejected by the extraction model: ${err.message}` };
  }
  if (err instanceof Anthropic.APIConnectionError) {
    return { statusCode: 502, error: "Could not reach the Anthropic API. Check connectivity and retry." };
  }
  if (err instanceof Anthropic.InternalServerError) {
    return { statusCode: 502, error: "Anthropic API is temporarily unavailable. Retry in a few minutes." };
  }
  return { statusCode: 500, error: err.message || "Extraction failed for an unknown reason." };
}

exports.handler = async (event) => {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers, body: JSON.stringify({ error: "Method not allowed" }) };
  }

  try {
    const { pdf_base64 } = JSON.parse(event.body);
    if (!pdf_base64) {
      return { statusCode: 400, headers, body: JSON.stringify({ error: "pdf_base64 is required" }) };
    }

    if (!process.env.ANTHROPIC_API_KEY) {
      return {
        statusCode: 500,
        headers,
        body: JSON.stringify({ error: "ANTHROPIC_API_KEY is not configured on this deploy." }),
      };
    }

    const { deed, model, degraded } = await extractDeed(pdf_base64);
    const warnings = validateDeed(deed);

    if (degraded) {
      console.error(`[extract-pdf] DEGRADED: primary model unavailable, extraction served by fallback "${model}"`);
    }
    if (warnings.length) {
      console.warn(`[extract-pdf] extraction warnings: ${warnings.join("; ")}`);
    }

    // Deed fields stay at the top level so existing callers keep working.
    // Underscore-prefixed keys carry the new diagnostics and cannot collide with
    // schema fields.
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ ...deed, _warnings: warnings, _model: model, _degraded: degraded }),
    };
  } catch (err) {
    const { statusCode, error } = describeFailure(err);
    console.error(`[extract-pdf] ${statusCode}: ${error}`, err.cause || err);
    return { statusCode, headers, body: JSON.stringify({ error }) };
  }
};
