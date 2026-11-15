function headerValue(event, name) {
  const headers = (event && event.headers) || {};
  const want = name.toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === want && value != null) return String(value);
  }
  return "";
}

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  };
}

function rawBody(event) {
  if (!event || event.body == null || event.body === "") return "";
  if (event.isBase64Encoded) return Buffer.from(event.body, "base64").toString("utf8");
  return String(event.body);
}

module.exports = { headerValue, jsonResponse, rawBody };
