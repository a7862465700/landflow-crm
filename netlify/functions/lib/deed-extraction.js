// Shared deed-extraction logic.
//
// Both the interactive import endpoint (extract-pdf.js) and the scheduled health
// check (model-health-canary.js) import from here, so the canary always exercises
// the same model configuration the real import uses.

const Anthropic = require("@anthropic-ai/sdk");

// Ordered model preference. The first entry is primary; later entries are only
// used when an earlier one is gone (HTTP 404). Overridable via the
// ANTHROPIC_MODELS env var so a retirement can be worked around by changing
// config in Netlify rather than shipping code.
//
// Use undated aliases here. Dated snapshots (e.g. claude-sonnet-4-20250514) are
// the ones on a published retirement clock — pinning one is what took deed
// imports down on 2026-06-15.
const MODELS = (process.env.ANTHROPIC_MODELS || "claude-sonnet-5,claude-opus-4-8")
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);

// Fields we refuse to trust silently. An empty value here means the deed did not
// yield the data — the caller surfaces that for human review rather than writing
// a blank or invented value into the loan record.
const REQUIRED_FIELDS = ["parcel", "legal_desc", "county", "filing_date"];

// Structured-output schema. The API guarantees a response conforming to this,
// which removes the need to regex a JSON object out of prose.
//
// Note: no `format: "date"` on filing_date and no minimum on price_paid. A
// required, format-constrained field forces the model to emit *something* even
// when the deed doesn't show it — which produces a confidently wrong date rather
// than an honest blank. We take "" / 0 and flag it in validateDeed() instead.
const DEED_SCHEMA = {
  type: "object",
  properties: {
    seller: { type: "string", description: "Commissioner name and title, e.g. 'Tommy Land, Commissioner of State Lands, State of Arkansas'" },
    seller_address: { type: "string", description: "Commissioner office address, or \"\" if absent" },
    parcel: { type: "string", description: "Parcel ID exactly as written, e.g. XX-XXXXX-XXX. \"\" if not found." },
    legal_desc: { type: "string", description: "Full legal description: section, township, range, lot, block, subdivision, addition." },
    county: { type: "string", description: "County name only, without the word 'County'" },
    city: { type: "string", description: "City or municipality, or \"\" if absent" },
    price_paid: { type: "number", description: "Dollar amount paid to the Commissioner of State Lands. 0 if not found." },
    previous_owner: { type: "string", description: "Tax-assessed previous owner who lost the property to the state" },
    filing_date: { type: "string", description: "Commissioner's official seal date, from the 'WITNESS MY HAND AND OFFICIAL SEAL, as Commissioner of State Lands, on this date ____' clause above the signature. YYYY-MM-DD. NOT the county clerk's recording stamp. \"\" if not legible — never substitute today's date." },
  },
  required: [
    "seller", "seller_address", "parcel", "legal_desc", "county",
    "city", "price_paid", "previous_owner", "filing_date",
  ],
  additionalProperties: false,
};

const PROMPT = `This is an Arkansas Limited Warranty Deed issued by the Commissioner of State Lands (Tommy Land or successor). Extract the deed fields.

Important notes:
- Do not put the grantee/purchasing company (the entity the deed conveys TO) in any field. Only the Commissioner side and the property belong in the output.

- filing_date is the COMMISSIONER'S OFFICIAL SEAL DATE — the date the Commissioner of
  State Lands executed the deed under seal, which the business treats as the funding
  date. It appears in the clause immediately above the signature block:

      "WITNESS MY HAND AND OFFICIAL SEAL, as Commissioner of State Lands,
       on this date July 13, 2026."

  This is standard Commissioner form language and reads the same on every deed
  regardless of county. The date is normally written out longhand
  (e.g. "March 05, 2026"). Return it as YYYY-MM-DD.

  These deeds carry several other dates. Do NOT use any of them:
    * the COUNTY CLERK'S RECORDING STAMP — top right of page one and/or in a
      certification block, next to a Book/Page or instrument number, and usually
      carrying a time of day. Wording varies by county, e.g.
      "eFiled for Record 07/16/2026 3:09PM" (Garland) or
      "I certify this instrument was filed on: 03/10/2026 03:32:19 PM" (Saline).
      This is typically a few days AFTER the seal date and is NOT the date we want.
    * "Year Forfeited" or the tax years assessed (e.g. "2020 - 2024")
    * today's date

  If the seal date is not legible, return an empty string. Never guess and never
  substitute a different date from the document.

- For price_paid, use the dollar amount paid to the Commissioner of State Lands
- Garland County and Saline County deeds have different layouts. In Garland County the parcel number often appears near the legal description; in Saline County it may be labeled "Parcel ID" or "Tax ID". Extract it exactly as written.
- If a field genuinely does not appear in the document, return an empty string (or 0 for price_paid). Do not infer or invent values.`;

/**
 * Run the extraction against the first available model.
 *
 * Falls through to the next configured model only on a 404 (the model no longer
 * exists). Every other error — rate limit, auth, unreadable PDF, server error —
 * is rethrown immediately: falling back on those would mask real problems and
 * bill the request twice.
 *
 * @returns {Promise<{ deed: object, model: string, degraded: boolean }>}
 */
async function extractDeed(pdfBase64, client) {
  const anthropic = client || new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  let lastNotFound;

  for (let i = 0; i < MODELS.length; i++) {
    const model = MODELS[i];
    try {
      const message = await anthropic.messages.create({
        model,
        max_tokens: 4096,
        // Keep reasoning off: this is an interactive import and the user is
        // waiting. Structured outputs already guarantee response shape.
        thinking: { type: "disabled" },
        output_config: { format: { type: "json_schema", schema: DEED_SCHEMA } },
        messages: [
          {
            role: "user",
            content: [
              { type: "document", source: { type: "base64", media_type: "application/pdf", data: pdfBase64 } },
              { type: "text", text: PROMPT },
            ],
          },
        ],
      });

      if (message.stop_reason === "max_tokens") {
        throw new Error("Extraction was cut off before completing — the legal description may be unusually long.");
      }

      const textBlock = message.content.find((b) => b.type === "text");
      if (!textBlock) {
        throw new Error("Model returned no text content for this deed.");
      }

      return { deed: JSON.parse(textBlock.text), model, degraded: i > 0 };
    } catch (err) {
      if (err.status !== 404) throw err;
      console.error(`[deed-extraction] model "${model}" returned 404 — trying next configured model`);
      lastNotFound = err;
    }
  }

  const exhausted = new Error(
    `No configured extraction model is available (tried: ${MODELS.join(", ")}). ` +
      `These models are likely retired — update the ANTHROPIC_MODELS environment variable.`
  );
  exhausted.status = 503;
  exhausted.cause = lastNotFound;
  throw exhausted;
}

/**
 * Check an extraction for values that must not be trusted silently.
 * Returns a list of human-readable warnings; empty means the deed looks complete.
 */
function validateDeed(deed) {
  const warnings = [];

  for (const field of REQUIRED_FIELDS) {
    const value = deed[field];
    if (value === undefined || value === null || String(value).trim() === "") {
      warnings.push(`${field.replace(/_/g, " ")} could not be read from the deed`);
    }
  }

  // filing_date drives the loan's origination and first-payment dates. A
  // malformed one silently becomes today's date in the UI, which produces a loan
  // that looks past-due the moment it is saved.
  if (deed.filing_date && !/^\d{4}-\d{2}-\d{2}$/.test(deed.filing_date)) {
    warnings.push(`filing date "${deed.filing_date}" is not a valid YYYY-MM-DD date`);
  }

  if (!(deed.price_paid > 0)) {
    warnings.push("price paid came back as 0 — confirm against the deed");
  }

  return warnings;
}

module.exports = { MODELS, DEED_SCHEMA, REQUIRED_FIELDS, extractDeed, validateDeed };
