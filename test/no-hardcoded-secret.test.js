const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");

function walk(dir, found) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".git" || entry.name === "test") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, found);
    else if (/\.(html|js|sql|toml|json|example|ps1)$/.test(entry.name) && entry.name !== "package-lock.json") {
      found.push(full);
    }
  }
  return found;
}

test("tracked source no longer contains the shared-secret assignment or a 64-hex literal", () => {
  const files = walk(ROOT, []);
  const hits = [];
  for (const file of files) {
    const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
    lines.forEach((line, index) => {
      if (line.includes("HSF_SYNC_SECRET")) hits.push(`${path.relative(ROOT, file)}:${index + 1} name`);
      if (/['"][0-9a-fA-F]{64}['"]/.test(line)) hits.push(`${path.relative(ROOT, file)}:${index + 1} hex-literal`);
    });
  }
  assert.deepEqual(hits, []);
});

test("the CRM page calls LandFlow functions instead of the portal with a secret", () => {
  const html = fs.readFileSync(path.join(ROOT, "landflow/index.html"), "utf8");
  assert.match(html, /\/\.netlify\/functions\/crm-sync/);
  assert.match(html, /\/\.netlify\/functions\/invite-lender/);
  assert.equal(html.includes("hickorystreetfinance.com/api/crm-sync"), false);
  assert.equal(html.includes("hickorystreetfinance.com/api/admin/invite-lender"), false);
  assert.match(html, /function signedInHeaders\(/);
});

test(".env.example lists names only and env files stay ignored", () => {
  const example = fs.readFileSync(path.join(ROOT, ".env.example"), "utf8");
  assert.match(example, /^HSF_CRM_SYNC_SECRET=/m);
  assert.match(example, /^SUPABASE_ANON_KEY=/m);
  assert.match(example, /^SUPABASE_URL=/m);
  assert.doesNotMatch(example, /eyJ[A-Za-z0-9_-]{10,}\./);
  assert.doesNotMatch(example, /['"][0-9a-fA-F]{32,}['"]/);
  const gitignore = fs.readFileSync(path.join(ROOT, ".gitignore"), "utf8");
  assert.match(gitignore, /^\.env\*$/m);
  assert.match(gitignore, /^!\.env\.example$/m);
});
