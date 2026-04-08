# Stack Research

**Domain:** IRS Form 1098 Tax Reporting — Owner-Finance Land Platform (Next.js/Supabase)
**Researched:** 2026-04-08
**Confidence:** HIGH for PDF generation and email delivery. MEDIUM for IRS compliance nuance.

---

## Context: What Already Exists (Do Not Re-Research)

This milestone adds to an already-deployed stack. The following are in production and need no changes:

- Next.js 14, React 18, TypeScript, Tailwind CSS (HSF platform)
- Supabase PostgreSQL + Auth + Storage (shared across repos)
- Netlify Pro (hosting)
- Resend (email notifications — already used for payment confirmations)
- pg_cron (scheduled jobs — already used for payment reminders)
- RBAC: admin, note_buyer, borrower roles with JWT hook + middleware

---

## New Libraries Required

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `@react-pdf/renderer` | ^4.4.0 | Generate 1098 PDF as React component | React-native component model means the form layout is maintainable TypeScript code, not coordinate math. Runs server-side via `renderToBuffer()` in Next.js API routes (App Router compatible since Next.js 14.1.1+). 860K weekly downloads, actively maintained as of April 2026. |
| `decimal.js` | ^10.4.3 | Precise interest calculations | JavaScript IEEE 754 floats produce rounding errors on financial arithmetic (e.g., 0.1 + 0.2 ≠ 0.3). `decimal.js` uses arbitrary-precision decimal math. Required for daily pro-ration of interest on mid-year note creation dates. Widely used in financial applications including Prisma's Decimal type. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@supabase/supabase-js` | already installed | Upload generated PDFs to Supabase Storage bucket | Upload the rendered PDF buffer to a `tax-documents` bucket so borrowers can retrieve it later without re-generating. Use service role key (bypasses RLS) from server API route. |
| `resend` | already installed | Email borrower with 1098 availability notification | Resend supports `attachments` array with base64 `content` + `filename`. Use for the January 31 automated email. 40MB size limit (PDFs are ~100KB, well within limit). |

No additional npm packages are needed beyond these two new installs.

---

## Installation

```bash
# From the HSF Next.js project root (village-vista/)
npm install @react-pdf/renderer decimal.js

# Type definitions (react-pdf includes its own — no @types needed)
```

---

## Architecture: How the Pieces Fit Together

### PDF Generation Flow

```
pg_cron job (Jan 1 each year)
  → calls Supabase Edge Function or Next.js API route: /api/admin/generate-1098s
  → queries payment_ledger for prior year interest per loan
  → decimal.js computes annual interest total with proper pro-ration
  → @react-pdf/renderer renderToBuffer() → Uint8Array PDF
  → supabase.storage.from('tax-documents').upload(`1098/${year}/${loan_id}.pdf`, buffer)
  → inserts row into tax_documents table (loan_id, year, storage_path, generated_at)
  → Resend email to borrower: "Your 1098 is ready" (with PDF as attachment OR portal link)
```

### Borrower Download Flow

```
Borrower portal page: /portal/tax-documents
  → queries tax_documents table filtered by borrower's loan_id
  → displays list of available 1098s by year
  → "Download" button → calls /api/portal/1098/[year] → returns signed Storage URL
```

### Admin Accountant Report Flow

```
Admin portal: /admin/reports/1098/[year]
  → queries payment_ledger grouped by borrower
  → decimal.js totals for each borrower
  → CSV download or printable table
  → No PDF generation needed for admin view — spreadsheet is more useful
```

---

## IRS Compliance Notes (HIGH confidence — verified against IRS.gov)

**What must be on Copy B (the borrower's copy):**

| Box | Field | Required |
|-----|-------|----------|
| Box 1 | Mortgage Interest Received | Yes — core field |
| Box 2 | Outstanding Mortgage Principal (Jan 1 of tax year) | Yes |
| Box 3 | Mortgage Origination Date | Yes |
| Box 4 | Refund of Overpaid Interest | Only if applicable |
| Box 7 | Address of Property Securing Mortgage | Yes |
| Box 11 | Mortgage Acquisition Date | If acquired mid-year |
| Lender name + TIN | Hot Springs Land entity info | Yes |
| Borrower name + TIN/SSN | Borrower's info | Yes |

**Filing threshold:** $600 or more of mortgage interest per loan per calendar year. Per-loan, not per-borrower aggregate.

**Copy B deadline:** January 31 of the year following the tax year (e.g., Jan 31, 2026 for tax year 2025). If Jan 31 falls on a weekend, next business day.

**Custom PDF for Copy B is acceptable.** IRS Publication 1179 allows substitute statements to recipients (Copy B). The format is at the lender's discretion as long as required boxes are present. Source: IRS.gov/forms-pubs/about-form-1098 + Publication 1179 Rev. 2025.

**Copy A (IRS filing copy) is NOT what we generate.** Copy A must be filed with the IRS via official carbonless paper forms OR e-filing (IRS FIRE system). Our platform generates only Copy B for borrowers. The accountant report in admin enables the human accountant to handle IRS filing. This is correct given e-filing is explicitly out of scope.

**Land contracts qualify as mortgages.** IRS treats land contracts (deed-not-transferred-until-payoff) as mortgages for 1098 reporting purposes when the lender can repossess. Hot Springs Land's owner-finance notes qualify.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `@react-pdf/renderer` | `pdf-lib` (v1.17.1) | Use pdf-lib if filling an existing IRS PDF template by field name. Avoid for this project: the official IRS PDF's AcroForm field names are not documented, and pdf-lib's core package is unmaintained (last release 4 years ago). For generating a custom-layout Copy B, react-pdf's component model is far superior. |
| `@react-pdf/renderer` | `@cantoo/pdf-lib` (v2.6.5) | Use this fork if you need to merge/manipulate existing PDFs. Actively maintained fork of pdf-lib with SVG support. Still less ergonomic than react-pdf for building form layouts from scratch. |
| `@react-pdf/renderer` | Puppeteer (HTML→PDF) | Use Puppeteer if the form layout is already in HTML/CSS. Not viable on Netlify (no headless Chrome). Would require a separate server or Lambda. Over-engineered for this use case. |
| `decimal.js` | Native JS math | Acceptable only if all interest figures come pre-rounded from the database as integer cents. If computing pro-ration (fractional days × daily rate), floating point errors will cause off-by-a-cent discrepancies. decimal.js is the safer default. |
| Supabase Storage | Store PDF as base64 in DB | Consistent with existing vault_files approach, but PDFs are binary blobs not suited for base64 in Postgres. Storage is the correct choice for generated files. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| IRS FIRE e-filing integration | Explicitly out of scope. Adds significant complexity (IRS credentialing, TCC number, test file submissions). Accountant handles IRS Copy A filing manually. | Admin accountant summary report (CSV/table) |
| Third-party 1098 services (TaxAct, Tax1099.com) | Adds a vendor dependency and monthly cost for something we can build precisely tailored to our data model in ~2 hours of work. | `@react-pdf/renderer` + custom template |
| Note buyer 1098 generation | Explicitly deferred to future milestone per PROJECT.md. Note buyers receive income, not mortgage interest — that is a different form (1099-INT). | Future milestone |
| SMS notifications for 1098 availability | SMS/Twilio is deferred per existing memory. Email via Resend is sufficient for January 31 delivery. | Resend email |
| Puppeteer / headless Chrome | Cannot run on Netlify. Would require a separate Lambda function just for PDF rendering. | `@react-pdf/renderer` (pure Node, no binary deps) |

---

## Next.js Configuration

Add to `next.config.js` for App Router compatibility:

```js
// next.config.js
module.exports = {
  experimental: {
    serverComponentsExternalPackages: ['@react-pdf/renderer'],
  },
}
```

This tells Next.js not to bundle react-pdf through its module graph for server components, preventing the "ba.Component is not a constructor" error seen in some Next.js 14 App Router setups.

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| `@react-pdf/renderer@4.4.0` | React 18, Next.js 14.1.1+ | Next.js 14 App Router had a crash bug fixed in 14.1.1. Confirm project is on ≥14.1.1 before using. `renderToBuffer()` works in Next.js API routes and Server Actions. |
| `decimal.js@10.4.3` | Node.js 14+, TypeScript | No peer dependency conflicts. Includes its own TypeScript types. |
| `@supabase/supabase-js` (existing) | Supabase Storage upload | `supabase.storage.from('tax-documents').upload(path, buffer, { contentType: 'application/pdf' })` accepts Uint8Array from `renderToBuffer()` directly. |
| `resend` (existing) | PDF attachment as base64 | Resend `attachments[].content` accepts Buffer. Convert Uint8Array from renderToBuffer: `Buffer.from(pdfBytes)`. 40MB attachment limit is not a concern (1098 PDFs ~50–150KB). |

---

## Sources

- [IRS Form 1098 Instructions (Rev. December 2026)](https://www.irs.gov/instructions/i1098) — Field box requirements, $600 threshold, filing obligations for owner-financers
- [IRS About Form 1098](https://www.irs.gov/forms-pubs/about-form-1098) — Substitute form (Publication 1179) reference confirming custom PDF Copy B is acceptable
- [IRS Publication 1179 (Rev. 2025)](https://www.irs.gov/pub/irs-pdf/p1179.pdf) — Substitute form rules; Copy B format is at filer's discretion
- [@react-pdf/renderer npm](https://www.npmjs.com/package/@react-pdf/renderer) — Version 4.4.0 confirmed, weekly downloads ~860K
- [react-pdf Next.js 14 compatibility issue](https://github.com/diegomura/react-pdf/issues/2460) — Documents App Router crash and `serverComponentsExternalPackages` workaround
- [pdf-lib npm](https://www.npmjs.com/package/pdf-lib) — Version 1.17.1, last published 4 years ago (unmaintained)
- [@cantoo/pdf-lib npm](https://www.npmjs.com/package/@cantoo/pdf-lib) — Active fork v2.6.5, maintained on as-needed basis
- [Resend attachments docs](https://resend.com/docs/dashboard/emails/attachments) — Base64 content attachment format, 40MB limit
- [decimal.js GitHub](https://github.com/MikeMcl/decimal.js/) — Arbitrary-precision decimal for JavaScript financial math
- [Supabase Storage uploads](https://supabase.com/docs/guides/storage/uploads/standard-uploads) — Buffer upload via JS SDK
- [IRS owner financing 1098 requirement](https://www.hallsirs.com/irs-rules-owner-financing/) — Land contracts qualify as mortgages for 1098 reporting
- [Comparing open source PDF libraries 2025](https://joyfill.io/blog/comparing-open-source-pdf-libraries-2025-edition) — Ecosystem overview confirming react-pdf vs pdf-lib positioning

---

*Stack research for: IRS Form 1098 tax reporting — HSF borrower portal*
*Researched: 2026-04-08*
