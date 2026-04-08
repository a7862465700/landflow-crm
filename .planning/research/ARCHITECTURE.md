# Architecture Research

**Domain:** IRS Form 1098 Tax Reporting — integration into existing HSF borrower portal
**Researched:** 2026-04-08
**Confidence:** HIGH

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Borrower Portal (Next.js 14)                 │
├──────────────────────┬──────────────────────┬────────────────────┤
│   /(portal)/tax-docs │  /api/tax/1098        │  /api/cron/        │
│   BorrowerTaxPage    │  GET → generate PDF   │  january-1098      │
│   (new page)         │  uses service role    │  (new cron route)  │
│   reads loan data    │  streams or stores    │  Jan 31 trigger    │
│   shows 1098 list    │  PDF to Storage       │  email borrowers   │
└──────────────────────┴──────────────────────┴────────────────────┘
         │                        │                      │
         ▼                        ▼                      ▼
┌──────────────────────────────────────────────────────────────────┐
│                       Supabase (shared)                           │
├─────────────────┬────────────────────┬───────────────────────────┤
│  loans          │  tax_1098_records  │  Storage: tax-documents/   │
│  payments       │  (new table)       │  {loan_id}/{year}.pdf      │
│  late_fees      │  year, interest    │  (private bucket, RLS)     │
│  user_roles     │  generated_at      │                            │
│  notification_  │  pdf_storage_path  │                            │
│  log            │  email_sent_at     │                            │
└─────────────────┴────────────────────┴───────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Admin Portal (/admin/*)                         │
│   /admin/tax-reports  — accountant summary view (new page)        │
│   reads tax_1098_records + interest view for all loans            │
└──────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| `tax_1098_records` table | Stores generated 1098 metadata per loan per year | Migration 008 |
| `v_annual_interest` SQL view | Aggregates interest per loan per year from `payments` | Postgres view, queried on demand |
| `/api/tax/1098` API route | Generates PDF, uploads to Storage, returns signed URL | Server-side, service role |
| `/(portal)/tax-docs` page | Borrower downloads their 1098 | Client component, existing pattern |
| `/admin/tax-reports` page | Accountant summary: all borrowers, all years | Admin component, existing pattern |
| `/api/cron/january-1098` route | Runs Jan 31, emails qualifying borrowers | Same shape as `payment-reminders` |
| `lib/interest.ts` | TypeScript interest calculation functions | Extracted from `balance.ts` logic |
| `lib/pdf-1098.ts` | PDF generation using `@react-pdf/renderer` | Server-only, returns Buffer |

---

## Recommended Project Structure

New files sit alongside existing ones — nothing is reorganized.

```
borrower-portal/
├── app/
│   ├── (portal)/
│   │   ├── tax-docs/
│   │   │   └── page.tsx          # Borrower: list and download 1098s
│   ├── (admin)/admin/
│   │   ├── tax-reports/
│   │   │   └── page.tsx          # Admin: accountant summary table
│   ├── api/
│   │   ├── tax/
│   │   │   └── 1098/
│   │   │       └── route.ts      # GET ?loanId=&year= → signed PDF URL
│   │   ├── cron/
│   │   │   ├── payment-reminders/
│   │   │   │   └── route.ts      # (existing)
│   │   │   └── january-1098/
│   │   │       └── route.ts      # NEW: January email cron
├── lib/
│   ├── interest.ts               # NEW: annual interest calculation
│   ├── pdf-1098.ts               # NEW: PDF generation (server only)
│   ├── balance.ts                # (existing — interest.ts extracts from here)
│   ├── email-templates.ts        # (existing — add 1098_available type)
│   └── types.ts                  # (existing — add Tax1098Record type)
├── supabase/
│   └── migrations/
│       └── 008_tax_1098.sql      # NEW: table + view + storage bucket + RLS
├── middleware.ts                 # (existing — add /tax-docs route)
```

### Structure Rationale

- **`/api/tax/1098`:** Single API route handles both on-demand generation and cached retrieval. Checks `tax_1098_records` first; generates only if missing.
- **`/api/cron/january-1098`:** Mirrors `payment-reminders` shape exactly — same auth pattern (CRON_SECRET), same notification_log dedup approach.
- **`lib/interest.ts`:** Extracts the year-filtered interest sum from `balance.ts`'s `calcRealBalance` logic. Keeps PDF generation testable independently.
- **`lib/pdf-1098.ts`:** Server-only file. Must not be imported by client components (Next.js will error on `@react-pdf/renderer` in browser bundles).

---

## Architectural Patterns

### Pattern 1: SQL View for Interest Aggregation

**What:** A Postgres view `v_annual_interest` joins `loans` and `payments`, summing `interest_portion` per loan per year. The API route queries this view rather than re-running amortization logic in TypeScript each time.

**When to use:** The `payments` table already stores `interest_portion` per payment (set at the time of each payment in `balance.ts`). For the 1098 we sum those stored values — no re-computation needed for completed payments.

**Trade-offs:**
- Pro: Simple SQL, fast for small datasets (HSF scale: tens of loans), queryable from admin report without API overhead.
- Pro: Handles mid-year originations automatically — only sums payments in the calendar year.
- Con: If `interest_portion` was not recorded on old payments, the sum will be incorrect. Mitigation: the API route falls back to TypeScript amortization recalculation when `interest_portion = 0` for a loan.

```sql
-- Migration 008
CREATE OR REPLACE VIEW v_annual_interest AS
SELECT
  p.loan_id,
  l.borrower,
  l.email,
  l.ssn,
  l.parcel,
  l.address,
  l.loan_amount,
  l.rate,
  l.orig_date,
  EXTRACT(YEAR FROM p.date::date) AS tax_year,
  SUM(p.interest_portion) AS total_interest,
  COUNT(p.id) AS payment_count
FROM payments p
JOIN loans l ON l.id = p.loan_id
WHERE p.interest_portion > 0
  AND p.status IS DISTINCT FROM 'failed'
GROUP BY
  p.loan_id, l.borrower, l.email, l.ssn,
  l.parcel, l.address, l.loan_amount, l.rate, l.orig_date,
  EXTRACT(YEAR FROM p.date::date);
```

### Pattern 2: Generate-then-Cache PDF in Supabase Storage

**What:** On first request for a given loan+year, the API generates the PDF and uploads it to `tax-documents/{loan_id}/{year}.pdf` in a private Supabase Storage bucket. Subsequent requests return a short-lived signed URL to the stored file.

**When to use:** 1098s do not change after generation (historical data). Storing them avoids regeneration on every download and gives the admin a persistent audit trail.

**Trade-offs:**
- Pro: Fast repeat downloads; Storage path is the canonical record.
- Pro: Netlify function timeout is 60s; generation runs once and is never repeated.
- Con: Requires `SUPABASE_SERVICE_ROLE_KEY` in the API route (already present for cron route, same pattern).
- Con: Adds Storage dependency — bucket must be created and private.

```typescript
// lib/pdf-1098.ts (server only — do not import in client components)
import { renderToBuffer } from '@react-pdf/renderer';
import { Form1098 } from '@/components/pdf/Form1098';

export async function generate1098Buffer(data: Form1098Data): Promise<Buffer> {
  return renderToBuffer(<Form1098 data={data} />);
}
```

```typescript
// app/api/tax/1098/route.ts (simplified)
export async function GET(request: Request) {
  const { loanId, year } = parseParams(request);
  const supabase = getServiceClient();

  // 1. Check cache
  const { data: cached } = await supabase
    .from('tax_1098_records')
    .select('pdf_storage_path')
    .eq('loan_id', loanId)
    .eq('tax_year', year)
    .maybeSingle();

  if (cached?.pdf_storage_path) {
    const { data } = await supabase.storage
      .from('tax-documents')
      .createSignedUrl(cached.pdf_storage_path, 300); // 5-minute URL
    return NextResponse.redirect(data.signedUrl);
  }

  // 2. Generate
  const interestData = await fetchInterestData(supabase, loanId, year);
  if (interestData.total_interest < 600) {
    return NextResponse.json({ error: 'Below $600 threshold' }, { status: 422 });
  }
  const buffer = await generate1098Buffer(interestData);
  const path = `${loanId}/${year}.pdf`;

  // 3. Upload to Storage
  await supabase.storage.from('tax-documents').upload(path, buffer, {
    contentType: 'application/pdf',
    upsert: true,
  });

  // 4. Record in tax_1098_records
  await supabase.from('tax_1098_records').upsert({
    loan_id: loanId, tax_year: year,
    total_interest: interestData.total_interest,
    pdf_storage_path: path,
    generated_at: new Date().toISOString(),
  });

  // 5. Return signed URL
  const { data: signedData } = await supabase.storage
    .from('tax-documents')
    .createSignedUrl(path, 300);
  return NextResponse.redirect(signedData.signedUrl);
}
```

### Pattern 3: January Cron Mirrors Existing Cron Shape

**What:** `/api/cron/january-1098` follows the exact same structure as `/api/cron/payment-reminders`: CRON_SECRET auth header, service-role Supabase client, loops over qualifying loans, sends via Resend, deduplicates using `notification_log`.

**When to use:** The January 1098 notification is a one-time-per-year email. Triggered by an external cron job (cron-job.org) on January 31 at 8am CT.

**Trade-offs:**
- Pro: No new infrastructure — same cron service, same secret, same dedup table.
- Con: January timing requires the cron job entry to be added manually to cron-job.org (same as payment-reminders was added).

```typescript
// Dedup key pattern — reuses notification_log
await supabase.from('notification_log').insert({
  loan_id: loan.id,
  notification_type: '1098_available',   // new type string
  billing_period: String(taxYear),       // e.g. "2025"
  sent_at: new Date().toISOString(),
});
```

---

## Data Flow

### Request Flow: Borrower Downloads 1098

```
Borrower clicks "Download 1098 (2025)"
    ↓
/(portal)/tax-docs/page.tsx
    ↓ fetch /api/tax/1098?loanId=xxx&year=2025
app/api/tax/1098/route.ts
    ↓ auth check: user owns this loan (loan.borrower_user_id = auth.uid())
    ↓ query tax_1098_records — cached?
    ├── YES → createSignedUrl → 302 redirect to signed URL
    └── NO  → query v_annual_interest
              ↓ interest >= $600?
              ├── NO  → 422 (below threshold, no 1098)
              └── YES → generate1098Buffer()
                        ↓ upload to Storage: tax-documents/{loan_id}/{year}.pdf
                        ↓ insert tax_1098_records row
                        ↓ createSignedUrl → 302 redirect
```

### Request Flow: January Email Cron

```
cron-job.org → POST /api/cron/january-1098 (Jan 31, 8am CT)
    ↓ CRON_SECRET auth
    ↓ query v_annual_interest WHERE tax_year = (current year - 1) AND total_interest >= 600
    ↓ for each qualifying loan:
        ↓ check notification_log (type='1098_available', period='2025') → dedup
        ↓ trigger /api/tax/1098 generation (upserts Storage + tax_1098_records)
        ↓ send email via Resend: "Your 2025 1098 is available at [portal link]"
        ↓ log to notification_log
```

### Request Flow: Admin Accountant Report

```
Admin visits /admin/tax-reports?year=2025
    ↓ server component: query v_annual_interest WHERE tax_year = 2025
    ↓ render table: borrower name, parcel, total interest, 1098 generated?
    ↓ download buttons per row (calls same /api/tax/1098 route)
    ↓ "Export CSV" button → client-side JSON → CSV conversion
```

---

## New Database Objects (Migration 008)

### Table: `tax_1098_records`

```sql
CREATE TABLE IF NOT EXISTS tax_1098_records (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id          uuid NOT NULL REFERENCES loans(id) ON DELETE RESTRICT,
  tax_year         integer NOT NULL,
  total_interest   numeric NOT NULL,
  pdf_storage_path text,              -- null until PDF generated
  generated_at     timestamptz,
  email_sent_at    timestamptz,       -- null until January email sent
  created_at       timestamptz DEFAULT now() NOT NULL,
  UNIQUE (loan_id, tax_year)
);

ALTER TABLE tax_1098_records ENABLE ROW LEVEL SECURITY;

-- Borrowers can read their own records
CREATE POLICY "Borrowers read own 1098 records"
  ON tax_1098_records FOR SELECT
  USING (
    loan_id IN (SELECT id FROM loans WHERE borrower_user_id = auth.uid())
  );

-- Admin can read all records
CREATE POLICY "Admins read all 1098 records"
  ON tax_1098_records FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin')
  );

-- Service role inserts/updates (API route uses service key)
GRANT SELECT ON tax_1098_records TO authenticated;
```

### View: `v_annual_interest` (see Pattern 1 above)

RLS note: Views in Postgres run with the security context of the querier. Wrap in an API route (service role) rather than querying directly from client — this avoids needing RLS on the view itself and keeps SSN data server-side only.

### Storage Bucket: `tax-documents`

```sql
-- Run in Supabase dashboard Storage or via SQL
INSERT INTO storage.buckets (id, name, public)
VALUES ('tax-documents', 'tax-documents', false);

-- RLS: borrowers can download their own PDFs
CREATE POLICY "Borrowers download own 1098 PDFs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'tax-documents'
    AND (storage.foldername(name))[1] IN (
      SELECT id::text FROM loans WHERE borrower_user_id = auth.uid()
    )
  );

-- Admin can download all
CREATE POLICY "Admins download all 1098 PDFs"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'tax-documents'
    AND EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'admin')
  );
```

---

## IRS Form 1098 Field Mapping

The PDF must include these fields (IRS-required boxes, source: [IRS Instructions for Form 1098](https://www.irs.gov/instructions/i1098)):

| IRS Box | Field Name | Source in HSF |
|---------|------------|---------------|
| Header: Recipient TIN | Lender EIN/SSN | `user_settings.ein` (add column) OR hardcoded from env |
| Header: Payer TIN | Borrower SSN | `loans.ssn` (already exists) |
| Header: Payer name/address | Borrower name + address | `loans.borrower`, `loans.address` |
| Box 1 | Mortgage Interest Received | `v_annual_interest.total_interest` |
| Box 2 | Outstanding Principal (Jan 1) | Balance as of Jan 1 of tax year (computed via `calcRealBalance` filtered to year-start) |
| Box 3 | Mortgage Origination Date | `loans.orig_date` |
| Box 7 | Address same as payer | Checkbox (likely unchecked — land parcels differ from mailing) |
| Box 8 | Property Address / Parcel | `loans.address` or `loans.parcel` |

Boxes 4 (refund), 5 (insurance), 6 (points), 9, 10, 11 are not applicable for this loan type and should be left blank.

**SSN display:** Render only last 4 digits on the borrower copy (`loans.ssn` exists but is stored as full SSN). The PDF generation function should mask it: `ssn.replace(/^\d{5}/, '*****')`.

---

## Interest Calculation: Stored vs. Recomputed

**Decision: Use stored `interest_portion` from `payments` table as the source of truth.**

Every payment recorded in HSF already has `interest_portion` set when the payment is processed (via `computePaymentSplit` in `lib/balance.ts`). The `v_annual_interest` view sums these stored values — no recomputation needed.

**Fallback for legacy/imported payments:** If a payment row has `interest_portion = 0` (imported from CRM before the portal existed), the API route should recompute the full amortization schedule using `calcRealBalance` and extract the year-specific interest total from `history`. This recomputation path needs to be gated so it only runs when the `v_annual_interest` result looks wrong (sum = 0 but payment_count > 0).

**Pro-ration for mid-year starts:** A loan originating in July 2025 will naturally have no payments before that date in the `payments` table, so the SUM is already pro-rated correctly. No special handling needed.

**Paid-off notes:** A loan with `status = 'paid_off'` still has payment rows. The view includes all loans, active or not. No special handling needed.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Current (< 50 loans) | On-demand PDF generation is fine; no queue needed |
| 50–500 loans | January batch email still runs serially in the cron route; add progress logging |
| 500+ loans | Background function or Supabase Edge Function for batch; queue per-loan jobs |

HSF is a small lender — the current architecture handles the full anticipated scale without queuing.

---

## Anti-Patterns

### Anti-Pattern 1: Computing Interest in TypeScript on Every Download

**What people do:** Run `calcRealBalance()` on every `/api/tax/1098` request to sum interest for a year.
**Why it's wrong:** Amortization recalculation iterates every payment row. For a 10-year loan with monthly payments, that's 120 rows per request. Already unnecessary since `interest_portion` is stored.
**Do this instead:** Query `v_annual_interest` (a simple `SUM` on pre-stored `interest_portion` values). Fall back to TypeScript recalculation only for loans that predate the portal (where `interest_portion = 0`).

### Anti-Pattern 2: Regenerating the PDF on Every Download Request

**What people do:** Call `renderToBuffer()` in the API route every time a borrower clicks download.
**Why it's wrong:** PDF generation takes ~500ms–2s, uses significant memory, and the 1098 content never changes after the tax year closes.
**Do this instead:** Generate once, store in Supabase Storage, return signed URL on subsequent requests. The `tax_1098_records.pdf_storage_path` field tracks whether generation has already happened.

### Anti-Pattern 3: Importing PDF Library in Client Components

**What people do:** Import `@react-pdf/renderer` in a `'use client'` component to show a preview or download button.
**Why it's wrong:** The renderer bundles `fontkit`, `pdfkit`, and other Node-specific modules. This breaks the Next.js client bundle and can add 1MB+ to the client JS payload.
**Do this instead:** Keep all PDF generation in `lib/pdf-1098.ts` (server-only). The client-side page only calls the `/api/tax/1098` route, which returns a redirect to a signed URL. No PDF code in the client.

### Anti-Pattern 4: Storing SSN in the PDF Metadata / Storage Path

**What people do:** Name the Storage file `{ssn}-2025.pdf` for easy lookup.
**Why it's wrong:** Supabase Storage paths can appear in logs, signed URLs, and browser history.
**Do this instead:** Use `{loan_id}/{year}.pdf` as the path. The loan_id is a UUID and carries no PII. Only use the SSN inside the PDF content itself, masked to last 4 digits on the borrower copy.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Resend API | Same as existing cron — direct HTTP POST in `/api/cron/january-1098` | Add `1098_available` email template to `lib/email-templates.ts` |
| Supabase Storage | Service-role upload in `/api/tax/1098`, signed URL for download | New private bucket `tax-documents`; already have service key in env |
| `@react-pdf/renderer` | Server-only in `lib/pdf-1098.ts` | ~860k weekly downloads, stable; do NOT import in client components |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `/(portal)/tax-docs` page → API | `fetch('/api/tax/1098?loanId=&year=')` | API returns 302 to signed URL; browser follows automatically |
| `/api/cron/january-1098` → Storage | Calls same generation logic as the download route | Extract generation logic into `lib/tax-generation.ts` so both cron and API route share it |
| Admin report page → DB | Direct Supabase query to `v_annual_interest` via server component | No separate API route needed for admin read — server components can use service role |
| middleware.ts → new routes | Add `/tax-docs` as `borrower` route and `/admin/tax-reports` is already under `/admin` | One-line addition to `ROLE_ROUTES` in middleware |

---

## Suggested Build Order

Dependencies drive this order:

1. **Migration 008** — `tax_1098_records` table, `v_annual_interest` view, `tax-documents` bucket, RLS policies. Everything else depends on this.

2. **`lib/interest.ts`** — Year-filtered interest extraction (falls back to TypeScript recalculation for pre-portal payments). Dependency for PDF generation and admin report.

3. **`lib/pdf-1098.ts`** — Form 1098 PDF component using `@react-pdf/renderer`. Requires interest data shape from step 2. Unit-testable in isolation.

4. **`/api/tax/1098` route** — Auth check, interest query, generate-and-cache logic, signed URL response. Depends on steps 1–3.

5. **`/(portal)/tax-docs` page** — Borrower UI. Depends on step 4. Also update `middleware.ts` to add `/tax-docs` as a `borrower` route.

6. **`/admin/tax-reports` page** — Admin accountant summary. Queries `v_annual_interest` directly via server component. Depends on step 1.

7. **`/api/cron/january-1098` route** — January email cron. Depends on steps 1 and 4 (reuses generation logic). Register new cron job on cron-job.org after deploy.

---

## Sources

- [IRS Instructions for Form 1098 (December 2026)](https://www.irs.gov/instructions/i1098) — Box requirements, $600 threshold, filing deadlines
- [IRS Form 1098 PDF (April 2025)](https://www.irs.gov/pub/irs-pdf/f1098.pdf) — Official form layout
- [Supabase Storage Access Control](https://supabase.com/docs/guides/storage/security/access-control) — RLS on storage.objects
- [Supabase createSignedUrl Reference](https://supabase.com/docs/reference/javascript/storage-from-createsignedurl) — Signed URL generation
- [@react-pdf/renderer npm](https://www.npmjs.com/package/@react-pdf/renderer) — 860k weekly downloads, server-side rendering confirmed
- [Netlify Function Limits](https://docs.netlify.com/build/functions/overview/) — 60s timeout, 1024MB memory, 6MB response limit (PDF well under limit)
- [PostgreSQL CREATE VIEW](https://www.postgresql.org/docs/current/sql-createview.html) — View behavior (not materialized, runs on query)

---
*Architecture research for: IRS Form 1098 integration into HSF borrower portal*
*Researched: 2026-04-08*
