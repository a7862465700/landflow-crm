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
              text: `Extract the following fields from this Arkansas deed document. Return ONLY valid JSON with these exact keys:

{
  "seller": "Commissioner name and title (e.g. Tommy Land, Commissioner of State Lands)",
  "seller_address": "Commissioner office address",
  "parcel": "Parcel number",
  "legal_desc": "Full legal description (section, township, range, lot, block, city, addition, etc.)",
  "county": "County name",
  "city": "City name if present",
  "price_paid": 0.00,
  "previous_owner": "Tax-assessed previous owner name",
  "filing_date": "YYYY-MM-DD"
}

For price_paid, use the dollar amount paid to the Commissioner. Return only the JSON, no other text.`,
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
