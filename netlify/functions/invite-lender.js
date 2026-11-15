const { forwardToHsf } = require("./lib/hsf-forward");

// Signed-in CRM users can ask Hickory Street Finance to invite a note buyer.
// The shared secret stays in the Netlify environment.
exports.handler = (event) =>
  forwardToHsf({
    event,
    upstreamPath: "/api/admin/invite-lender",
    buildBody(payload) {
      const email = String(payload.email || "")
        .trim()
        .toLowerCase()
        .replace(/^mailto:/, "")
        .trim();
      if (!email.includes("@") || email.length > 320 || email.includes(" ")) {
        return { error: "A valid email is required." };
      }
      const name = String(payload.name || "").trim().slice(0, 200);
      const businessName = String(payload.businessName || "").trim().slice(0, 200);
      return { body: { email, name, businessName } };
    },
  });
