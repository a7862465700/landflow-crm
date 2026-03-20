const Anthropic = require("@anthropic-ai/sdk");

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

    const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

    const message = await client.messages.create({
      model: "claude-sonnet-4-20250514",
      max_tokens: 1024,
      messages: [
        {
          role: "user",
          content: [
            {
              type: "document",
              source: { type: "base64", media_type: "application/pdf", data: pdf_base64 },
            },
            {
              type: "text",
              text: `This is an Arkansas Limited Warranty Deed issued by the Commissioner of State Lands (Tommy Land or successor). Extract the following fields and return ONLY valid JSON with these exact keys:

{
  "seller": "Commissioner name and title (e.g. Tommy Land, Commissioner of State Lands, State of Arkansas)",
  "seller_address": "Commissioner office address",
  "parcel": "Parcel ID or parcel number — look for a format like XX-XXXXX-XXX or similar county assessor ID. In Garland County deeds this may appear as a parcel number near the legal description. In Saline County deeds it may be labeled 'Parcel ID' or 'Tax ID'. Extract the full number exactly as written.",
  "legal_desc": "Full legal description including section, township, range, lot, block, subdivision, city, addition, or any other identifying language as written in the deed.",
  "county": "County name only (e.g. Garland, Saline) — do not include the word County",
  "city": "City or municipality name if present, otherwise empty string",
  "price_paid": 0.00,
  "previous_owner": "Name of the tax-assessed previous owner (the party who lost the property to the state for delinquent taxes)",
  "filing_date": "The date shown at the top right of the document in YYYY-MM-DD format — this is the deed execution or filing date, NOT today's date"
}

Important notes:
- The grantee/buyer is always Terra Equity Holdings — do not include this in any field
- filing_date must come from the document itself (top right corner), not the current date
- For price_paid, use the dollar amount paid to the Commissioner of State Lands
- Garland County and Saline County deeds have different layouts — extract parcel ID carefully from both
- Return only the JSON object, no explanation or markdown`,
            },
          ],
        },
      ],
    });

    const text = message.content[0].text.trim();
    // Parse JSON from response, handling potential markdown code blocks
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      return { statusCode: 500, headers, body: JSON.stringify({ error: "Failed to parse extraction result" }) };
    }

    const extracted = JSON.parse(jsonMatch[0]);
    return { statusCode: 200, headers, body: JSON.stringify(extracted) };
  } catch (err) {
    console.error("Extract PDF error:", err);
    return { statusCode: 500, headers, body: JSON.stringify({ error: err.message }) };
  }
};
