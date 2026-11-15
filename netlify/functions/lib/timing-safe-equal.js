const crypto = require("crypto");

/**
 * Compare two strings without leaking their contents through an early exit.
 * A length mismatch still returns false; the dummy compare keeps the
 * equal-length path from being the only call to the crypto helper.
 */
function timingSafeEqualString(left, right) {
  const a = Buffer.from(String(left), "utf8");
  const b = Buffer.from(String(right), "utf8");
  if (a.length !== b.length) {
    crypto.timingSafeEqual(a, a);
    return false;
  }
  return crypto.timingSafeEqual(a, b);
}

module.exports = { timingSafeEqualString };
