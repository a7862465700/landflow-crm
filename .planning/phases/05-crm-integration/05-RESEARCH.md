# Phase 5: CRM Integration - Research

**Researched:** 2026-04-04
**Domain:** Supabase Postgres triggers, Next.js API routes, cross-app sync
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

CONTEXT.md does not exist yet for this phase. Constraints are sourced from the additional
context block provided at research time and from verified codebase archaeology.

### Locked Decisions (from additional context block)
- Postgres trigger + Next.js API route for auto-sync (not a cron job)
- "Push to HSF" manual button in LandFlow CRM
- Upsert on `hsf_loans` keyed by `crm_loan_id` for deduplication
- Trigger fires when `nb_email` AND `inv_date` are both set on a `loans` row
- Sync fails with validation error written to `hsf_sync_errors` — no corruption of existing data

### Claude's Discretion
- Exact `hsf_loans` column names and types (no pre-existing table)
- API route path (e.g., `/api/crm-sync`)
- Admin UI placement for sync status in loan list
- Exact error display format

### Deferred Ideas (OUT OF SCOPE)
- Cron-based sync (trigger is faster and more reliable)
- Two-way sync back from HSF to CRM
- Real-time WebSocket updates
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CRM-01 | Setting nb_email and inv_date on a LandFlow parcel causes a loan record to appear in HSF within one cron cycle (no manual action needed) | Postgres trigger on `loans` table fires on UPDATE — calls a Next.js API route; satisfies "automatic, no manual action" |
| CRM-02 | Clicking "Push to HSF" in LandFlow CRM creates or updates the correct loan record in HSF | CRM already calls external API routes (pattern: `syncPhotosToWebsite`); same fetch pattern to `/api/crm-sync` |
| CRM-03 | A sync with missing required fields fails validation and writes a record to hsf_sync_errors without corrupting existing data | New `hsf_sync_errors` table; API route validates before upsert; errors recorded on failure paths |
| CRM-04 | Admin can see sync status (last synced, error state) for each loan in the admin loan list | `hsf_loans` stores `last_synced_at` + `sync_error`; HSF admin loan list fetches these columns via join |
| CRM-05 | Running the same sync twice for the same parcel does not create duplicate loans | Upsert on `crm_loan_id` (loans.id from CRM); `ON CONFLICT (crm_loan_id) DO UPDATE` |
</phase_requirements>

---

## Summary

Phase 5 bridges the LandFlow CRM (vanilla JS SPA using Supabase directly) and the Hickory Street Finance borrower portal (Next.js 14). When Richard assigns a note — setting `nb_email` and `inv_date` on a `loans` row — the corresponding HSF loan record must appear automatically. The chosen architecture is a Postgres `AFTER UPDATE` trigger on the `loans` table that calls an HSF API route via `pg_net` (Supabase's built-in HTTP extension), plus a "Push to HSF" button in the CRM for manual fallback.

Both apps share the same Supabase project (`rcidwqyrrfrthujymncn.supabase.co`). No Edge Functions or Supabase CLI are needed — the trigger uses `pg_net.http_post()` which is available in all Supabase hosted projects. The HSF portal already has this same service-role pattern in `app/api/admin/transfer/route.ts` and `app/api/sync-photos/route.ts` — the new `/api/crm-sync` route follows the exact same pattern.

Two new database artifacts are needed: `hsf_loans` table (where synced note data lives in HSF) and `hsf_sync_errors` table (validation failure log). The `hsf_loans` table uses `crm_loan_id` as the dedup key so running the same sync twice is idempotent.

**Primary recommendation:** Create `hsf_loans` + `hsf_sync_errors` tables via SQL migration, implement the trigger with `pg_net`, build a `/api/crm-sync` POST route in the borrower portal, add the "Push to HSF" button to the CRM, and surface sync status in the admin loan list.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@supabase/supabase-js` | ^2.101.1 (installed) | DB client in Next.js API route | Already in project |
| `pg_net` Supabase extension | Built-in (hosted) | HTTP calls from Postgres triggers | Standard Supabase mechanism for trigger-to-HTTP |
| Next.js 14 App Router | 14.2.5 (installed) | API route for `/api/crm-sync` | Already established stack |
| TypeScript | ^5 (installed) | Type safety in route handler | Already established |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `createClient` with service role | Already used in project | Bypass RLS for cross-app writes | Needed — hsf_loans has RLS, trigger/CRM cannot authenticate as admin |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| pg_net trigger | Supabase Edge Function | Edge Functions require Supabase CLI + deploy step; pg_net works with SQL migration alone |
| pg_net trigger | Supabase Database Webhook (Dashboard UI) | Webhooks work but can't be version-controlled easily; trigger SQL is in a migration file |
| pg_net trigger | Netlify Scheduled Function (cron) | Cron has latency (minutes), trigger fires instantly on UPDATE |

**Installation:** No new packages required. Everything is already installed.

---

## Architecture Patterns

### How the Trigger Calls the API Route

Supabase hosted projects have `pg_net` pre-installed. `pg_net.http_post()` sends an async
HTTP request from within a Postgres function. The trigger fires on `AFTER UPDATE` when both
`nb_email` and `inv_date` transition from null/empty to having values.

```sql
-- Source: Supabase pg_net extension (built-in on hosted projects)
-- Pattern: trigger calls HSF API route with service-role key in Authorization header
CREATE OR REPLACE FUNCTION trigger_crm_sync_to_hsf()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only fire when nb_email and inv_date are both newly set
  IF (NEW.nb_email IS NOT NULL AND NEW.nb_email <> '')
     AND (NEW.inv_date IS NOT NULL)
     AND (OLD.nb_email IS DISTINCT FROM NEW.nb_email
          OR OLD.inv_date IS DISTINCT FROM NEW.inv_date)
  THEN
    PERFORM pg_net.http_post(
      url := current_setting('app.hsf_sync_url'),
      body := jsonb_build_object('crm_loan_id', NEW.id)::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.hsf_sync_secret')
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_loan_assigned_sync_to_hsf
  AFTER UPDATE ON loans
  FOR EACH ROW
  EXECUTE FUNCTION trigger_crm_sync_to_hsf();
```

**CRITICAL NOTE on `pg_net` and config:** `current_setting('app.hsf_sync_url')` requires the
setting to be in the database config. The alternative — hardcoding the URL and secret — is
simpler but couples the trigger to the deployment URL. The pragmatic approach for this project:
use `ALTER DATABASE ... SET app.hsf_sync_url = '...'` in the migration itself (the URL is
known and stable: `https://hickorystreetfinance.com/api/crm-sync`).

The sync secret protects `/api/crm-sync` from unauthorized calls. It is a shared secret stored
as a Supabase DB setting AND an environment variable in the borrower portal.

### API Route Pattern (mirrors existing transfer route)

```typescript
// app/api/crm-sync/route.ts — Source: mirrors existing transfer/route.ts pattern
import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

const SYNC_SECRET = process.env.HSF_CRM_SYNC_SECRET!;

export async function POST(request: Request) {
  // 1. Verify shared secret from Authorization header
  const auth = request.headers.get('authorization') ?? '';
  if (auth !== `Bearer ${SYNC_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // 2. Parse crm_loan_id from body
  const { crm_loan_id } = await request.json();

  // 3. Service-role client (bypasses RLS)
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );

  // 4. Fetch source loan from CRM loans table
  const { data: loan, error: fetchError } = await supabase
    .from('loans')
    .select('id, borrower, email, phone, loan_amount, rate, term, orig_date, first_pay_date, nb_name, nb_email, nb_business, inv_date, inv_price, parcel, address, status')
    .eq('id', crm_loan_id)
    .single();

  if (fetchError || !loan) {
    await recordSyncError(supabase, crm_loan_id, 'LOAN_NOT_FOUND', fetchError?.message ?? 'Loan not found');
    return NextResponse.json({ error: 'Loan not found' }, { status: 404 });
  }

  // 5. Validate required fields
  const validationErrors: string[] = [];
  if (!loan.nb_email) validationErrors.push('nb_email is required');
  if (!loan.inv_date) validationErrors.push('inv_date is required');
  if (!loan.borrower) validationErrors.push('borrower name is required');
  if (!loan.loan_amount) validationErrors.push('loan_amount is required');

  if (validationErrors.length > 0) {
    await recordSyncError(supabase, crm_loan_id, 'VALIDATION_FAILED', validationErrors.join('; '));
    return NextResponse.json({ error: 'Validation failed', details: validationErrors }, { status: 422 });
  }

  // 6. Upsert into hsf_loans — crm_loan_id is the dedup key
  const { error: upsertError } = await supabase
    .from('hsf_loans')
    .upsert({
      crm_loan_id: loan.id,
      borrower: loan.borrower,
      email: loan.email,
      phone: loan.phone,
      loan_amount: loan.loan_amount,
      rate: loan.rate,
      term: loan.term,
      orig_date: loan.orig_date,
      first_pay_date: loan.first_pay_date,
      nb_name: loan.nb_name,
      nb_email: loan.nb_email,
      nb_business: loan.nb_business,
      inv_date: loan.inv_date,
      inv_price: loan.inv_price,
      parcel: loan.parcel,
      address: loan.address,
      last_synced_at: new Date().toISOString(),
      sync_error: null,  // clear any prior error on success
    }, {
      onConflict: 'crm_loan_id',
    });

  if (upsertError) {
    await recordSyncError(supabase, crm_loan_id, 'UPSERT_FAILED', upsertError.message);
    return NextResponse.json({ error: upsertError.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}

async function recordSyncError(supabase: any, crm_loan_id: string, code: string, detail: string) {
  await supabase.from('hsf_sync_errors').insert({
    crm_loan_id,
    error_code: code,
    error_detail: detail,
  });
}
```

### CRM "Push to HSF" Button Pattern

The CRM already calls external APIs using this exact pattern (see `syncPhotosToWebsite` in
`landflow/index.html`). The new button follows the same structure:

```javascript
// In landflow/index.html — mirrors syncPhotosToWebsite() pattern
async function pushToHSF(loanId) {
  showToast('Syncing to Hickory Street Finance...', 'info');
  try {
    const res = await fetch('https://hickorystreetfinance.com/api/crm-sync', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + HSF_SYNC_SECRET
      },
      body: JSON.stringify({ crm_loan_id: loanId })
    });
    const data = await res.json();
    if (!res.ok) {
      showToast('HSF sync failed: ' + (data.error || 'Unknown error'), 'error');
    } else {
      showToast('Sent to Hickory Street Finance', 'success');
    }
  } catch (e) {
    showToast('HSF sync error: ' + e.message, 'error');
  }
}
```

**Button placement:** In the note buyer section of the loan detail panel, rendered only when
`nb_email` and `inv_date` are set (same conditional gate as the trigger).

### hsf_loans Table Design

```sql
-- New table in shared Supabase — ADDITIVE, no drops
CREATE TABLE IF NOT EXISTS hsf_loans (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crm_loan_id      uuid NOT NULL UNIQUE REFERENCES loans(id) ON DELETE RESTRICT,
  borrower         text NOT NULL,
  email            text NOT NULL,
  phone            text,
  loan_amount      numeric NOT NULL,
  rate             numeric,
  term             integer,
  orig_date        date,
  first_pay_date   date,
  nb_name          text,
  nb_email         text NOT NULL,
  nb_business      text,
  inv_date         date NOT NULL,
  inv_price        numeric,
  parcel           text,
  address          text,
  last_synced_at   timestamptz NOT NULL DEFAULT now(),
  sync_error       text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hsf_loans ENABLE ROW LEVEL SECURITY;

-- Admin sees all hsf_loans
CREATE POLICY "Admin sees all hsf_loans"
  ON hsf_loans FOR SELECT
  USING (auth.uid() IN (SELECT user_id FROM user_roles WHERE role = 'admin'));

-- Service role key bypasses RLS — no additional policy needed for the sync route
```

### hsf_sync_errors Table Design

```sql
CREATE TABLE IF NOT EXISTS hsf_sync_errors (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  crm_loan_id   uuid,  -- nullable: may not have valid ID if trigger misfires
  error_code    text NOT NULL,
  error_detail  text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE hsf_sync_errors ENABLE ROW LEVEL SECURITY;

-- Admin sees all sync errors
CREATE POLICY "Admin sees all sync errors"
  ON hsf_sync_errors FOR SELECT
  USING (auth.uid() IN (SELECT user_id FROM user_roles WHERE role = 'admin'));
```

### Admin Loan List: Sync Status Column

The existing `AdminDashboardClient.tsx` queries `loans` via `supabase.from('loans').select('*')`.
The sync status lives in `hsf_loans`, not in `loans`. Two options:

1. **Join in the query:** `supabase.from('loans').select('*, hsf_loans(last_synced_at, sync_error)')`
   — works with Supabase PostgREST foreign key relationships.
2. **Separate query + merge client-side:** Two queries, merged by `crm_loan_id`.

Option 1 is cleaner. The `hsf_loans` table has `crm_loan_id uuid UNIQUE REFERENCES loans(id)` —
PostgREST exposes this as a one-to-one embed automatically.

```typescript
// In AdminDashboardPage — server component already fetches loans
const loansRes = await supabase
  .from('loans')
  .select('*, hsf_loans(last_synced_at, sync_error)')
  .order('created_at', { ascending: false });
```

Then in the table, add a "HSF Sync" column showing the `last_synced_at` date or an error badge.

### Recommended Project Structure (New Files)

```
borrower-portal/
├── app/
│   └── api/
│       └── crm-sync/
│           └── route.ts              # New: sync endpoint
├── supabase/
│   └── migrations/
│       └── 006_crm_integration.sql   # New: hsf_loans, hsf_sync_errors, trigger
```

```
landflow/
└── landflow/
    └── index.html                    # Modified: add pushToHSF(), "Push to HSF" button
```

### Anti-Patterns to Avoid

- **Hardcoding the sync secret in CRM client-side JS:** The CRM secret IS visible in the
  browser (vanilla JS, no build step). Accept this risk — the endpoint only upserts, never
  deletes. The secret prevents random internet callers but is not a strong security boundary.
  Acceptable for internal tooling. Document this.
- **Using `pg_net` without confirming it's enabled:** `pg_net` is available on all Supabase
  hosted projects but must be enabled in the dashboard: Database > Extensions > pg_net. Verify
  before relying on the trigger.
- **Forgetting CORS for the manual CRM button:** The CRM (landflowcrm.com or localhost) calls
  the borrower-portal API. The `/api/crm-sync` route needs CORS headers matching the same
  pattern as `/api/sync-photos` in village-vista.
- **Letting the trigger fire on every UPDATE:** The trigger condition must check that `nb_email`
  and `inv_date` are non-null AND that at least one of them changed (`IS DISTINCT FROM`). Without
  this, every loan save (e.g., updating payment status) would trigger a sync call.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dedup on re-sync | Custom check-then-insert logic | `upsert` with `onConflict: 'crm_loan_id'` | Race conditions in check-then-insert; upsert is atomic |
| HTTP from Postgres trigger | Custom queue or polling | `pg_net.http_post()` | Already installed in Supabase hosted; single SQL call |
| RLS bypass in API route | Anon key + policy gymnastics | `SUPABASE_SERVICE_ROLE_KEY` | Same pattern used in transfer/route.ts and sync-photos — established pattern |

**Key insight:** The hardest part of this phase is the Postgres trigger + pg_net setup. The
rest is a standard Next.js API route following patterns already in the codebase.

---

## Common Pitfalls

### Pitfall 1: pg_net Not Enabled
**What goes wrong:** Trigger function created but `pg_net.http_post()` throws `function not found` error; no sync fires.
**Why it happens:** `pg_net` is available but disabled by default on some Supabase plans.
**How to avoid:** Check Database > Extensions in the Supabase dashboard and enable `pg_net` before running the migration. Add a `CREATE EXTENSION IF NOT EXISTS pg_net` line in the migration as a guard.
**Warning signs:** Trigger exists but no HTTP calls arrive at the API route; no errors in Postgres logs either.

### Pitfall 2: Trigger Fires on Every Loan Save
**What goes wrong:** Every edit to any field on any loan (payment status, notes update) triggers an HSF sync call — even for loans that have no `nb_email`/`inv_date`.
**Why it happens:** Missing `IS DISTINCT FROM` check in the trigger condition.
**How to avoid:** Condition must check both that the new values are non-null AND that at least one changed: `(OLD.nb_email IS DISTINCT FROM NEW.nb_email OR OLD.inv_date IS DISTINCT FROM NEW.inv_date)`.
**Warning signs:** `hsf_sync_errors` fills up with `LOAN_NOT_FOUND` or `VALIDATION_FAILED` entries for loans that were never assigned.

### Pitfall 3: CORS Blocking the Manual CRM Button
**What goes wrong:** "Push to HSF" button in CRM triggers a network error in the browser console — CORS preflight fails.
**Why it happens:** `/api/crm-sync` route doesn't return `Access-Control-Allow-Origin` for the CRM's origin.
**How to avoid:** Implement the same CORS pattern as `sync-photos/route.ts` in village-vista — export an `OPTIONS` handler, add `getCorsHeaders()` function, include known CRM origins.
**Warning signs:** Browser shows `CORS error` or `blocked by CORS policy` in console when button is clicked.

### Pitfall 4: Sync Secret Visible in CRM Bundle
**What goes wrong:** `HSF_SYNC_SECRET` is hardcoded in `index.html` (vanilla JS, no build step) — visible to anyone who views source.
**Why it happens:** CRM has no server-side rendering or build step; secrets cannot be hidden.
**How to avoid:** Accept the limitation. Document that the endpoint only upserts data — it cannot delete or read sensitive data. The secret provides a basic "is this from our CRM" check, not strong authentication. This is a known acceptable risk for internal tooling.
**Warning signs:** N/A — this is by design, not a runtime error.

### Pitfall 5: PostgREST Embed Naming
**What goes wrong:** `supabase.from('loans').select('*, hsf_loans(last_synced_at)')` returns empty array for `hsf_loans` instead of the expected object.
**Why it happens:** PostgREST uses the foreign key constraint name to determine the embed relationship. If `crm_loan_id REFERENCES loans(id)` is set up correctly, the embed name is `hsf_loans`. But if the FK has an unusual name, the embed key might differ.
**How to avoid:** Test the embed query in the Supabase SQL editor or table editor before wiring the UI. Use `hsf_loans!crm_loan_id(...)` to explicitly specify the FK column if auto-detection fails.
**Warning signs:** `hsf_loans` key is absent or empty in query results despite data existing.

---

## Code Examples

### pg_net HTTP Post (Trigger Pattern)

```sql
-- Source: Supabase pg_net docs (https://supabase.com/docs/guides/database/extensions/pg_net)
-- Fire-and-forget async HTTP POST from a trigger
PERFORM pg_net.http_post(
  url     := 'https://hickorystreetfinance.com/api/crm-sync',
  body    := jsonb_build_object('crm_loan_id', NEW.id::text)::text,
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer <secret>'
  )
);
```

### Upsert with Conflict Key (PostgREST)

```typescript
// Source: Supabase docs (https://supabase.com/docs/reference/javascript/upsert)
const { error } = await supabase
  .from('hsf_loans')
  .upsert(
    { crm_loan_id: '...', borrower: '...', /* other fields */ },
    { onConflict: 'crm_loan_id' }
  );
```

### PostgREST One-to-One Embed

```typescript
// Source: Supabase docs (https://supabase.com/docs/guides/database/joins-and-nesting)
// hsf_loans has `crm_loan_id uuid REFERENCES loans(id)` — PostgREST exposes it as embed
const { data } = await supabase
  .from('loans')
  .select('*, hsf_loans(last_synced_at, sync_error)')
  .order('created_at', { ascending: false });
// data[i].hsf_loans is either null (never synced) or { last_synced_at, sync_error }
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Node.js | Building/running portal | Yes | v24.14.0 | — |
| @supabase/supabase-js | API route service client | Yes | ^2.101.1 | — |
| pg_net Postgres extension | Auto-sync trigger | Unknown (Supabase hosted) | Built-in | Manual button covers gap |
| SUPABASE_SERVICE_ROLE_KEY env var | API route | Yes (already used in project) | — | — |
| HSF_CRM_SYNC_SECRET env var | API route auth + CRM button | Not yet set | — | Must add to Netlify + DB config |
| hickorystreetfinance.com domain | Trigger URL target | Unknown (not verified in research) | — | Use localhost:3000 for dev |

**Missing dependencies with no fallback:**
- `HSF_CRM_SYNC_SECRET` — must be generated and added to Netlify environment variables AND stored as a Supabase DB setting (`ALTER DATABASE postgres SET app.hsf_sync_secret = '...'`). Plan must include this step.

**Missing dependencies with fallback:**
- `pg_net` extension — if disabled, auto-sync trigger will not fire. Manual "Push to HSF" button (CRM-02) covers this gap. Enable pg_net as part of Wave 0 setup verification.

---

## Validation Architecture

nyquist_validation key is absent from config.json — treating as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None installed (no jest, vitest, or pytest found in package.json) |
| Config file | None — Wave 0 gap |
| Quick run command | Manual smoke test via browser + Supabase dashboard |
| Full suite command | Manual end-to-end: trigger a loan update, check hsf_loans row appears |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CRM-01 | UPDATE loans with nb_email+inv_date causes hsf_loans row | smoke/manual | Check `hsf_loans` in Supabase dashboard after CRM save | No automated test infra |
| CRM-02 | "Push to HSF" button in CRM creates/updates hsf_loans row | smoke/manual | Click button in CRM, verify row in dashboard | No automated test infra |
| CRM-03 | Sync with missing fields writes to hsf_sync_errors without corruption | smoke/manual | POST to `/api/crm-sync` with incomplete loan, check error table | No automated test infra |
| CRM-04 | Admin loan list shows last_synced_at and error state | visual/manual | Load `/admin`, verify sync column renders | No automated test infra |
| CRM-05 | Two syncs of same parcel = one row (not two) | smoke/manual | Press "Push to HSF" twice, count hsf_loans rows | No automated test infra |

### Sampling Rate

- **Per task commit:** Manually verify in Supabase dashboard + browser
- **Per wave merge:** Full CRM-01 through CRM-05 smoke checklist
- **Phase gate:** All 5 success criteria TRUE before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] No automated test framework — all verification is manual smoke testing
- [ ] `HSF_CRM_SYNC_SECRET` environment variable must be generated and configured before any testing

*(Manual testing is acceptable here: this is an internal admin tool with low complexity and no test framework installed.)*

---

## Project Constraints (from CLAUDE.md)

The borrower portal has an explicit CLAUDE.md. Extracted directives:

| Directive | Source |
|-----------|--------|
| Tech stack is locked: Next.js 14 + Supabase + Tailwind | CLAUDE.md Constraints |
| Hosting: Netlify Pro (same as hotspringsland.com) | CLAUDE.md Constraints |
| Schema changes must be ADDITIVE — no drops, no breaking LandFlow or hotspringsland.com | CLAUDE.md Constraints |
| Use GSD workflow for all work (`/gsd:execute-phase` entry point) | CLAUDE.md GSD Workflow |
| Payments via Stripe ACH (irrelevant to this phase) | CLAUDE.md Constraints |
| Auth: Supabase Auth with RBAC (admin role required for sync status view) | CLAUDE.md Constraints |

**CRM has no CLAUDE.md** — follow existing vanilla JS patterns from `index.html`.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Supabase webhooks (dashboard UI config) | pg_net in SQL migration | 2024+ | Trigger is version-controlled in a migration file |
| `pg_net.http_request()` | `pg_net.http_post()` | pg_net v0.2+ | `http_post()` is the simpler shorthand; both work |

**Confirmed current:**
- Supabase upsert with `onConflict` is the idiomatic dedup pattern (HIGH confidence — official Supabase JS docs)
- `pg_net` is pre-installed on all Supabase hosted projects as of 2023 (HIGH confidence — Supabase docs)
- PostgREST foreign key embeds work via `table!fk_column(cols)` syntax (HIGH confidence — Supabase PostgREST docs)

---

## Open Questions

1. **Is `pg_net` already enabled in this Supabase project?**
   - What we know: `pg_net` is available on all hosted Supabase projects
   - What's unclear: Whether it was manually enabled in this specific project's database
   - Recommendation: Plan must include a Wave 0 step to verify/enable pg_net in the Supabase Dashboard (Database > Extensions > pg_net). The migration should also include `CREATE EXTENSION IF NOT EXISTS pg_net` as a guard.

2. **What is the deployed URL for the borrower portal?**
   - What we know: CLAUDE.md says Netlify Pro, same as hotspringsland.com
   - What's unclear: The actual domain (is it `hickorystreetfinance.com` or different?)
   - Recommendation: Plan should include a placeholder `HSF_SYNC_URL` that Richard sets when deploying. The DB setting and CRM constant both reference this variable.

3. **Should the CRM "Push to HSF" button be visible on all loans or only assigned ones?**
   - What we know: The trigger only fires when `nb_email` and `inv_date` are set
   - What's unclear: Whether Richard wants the button always visible (with a validation error if fields are missing) or hidden until fields are set
   - Recommendation: Show button only when `loan.nb_email && loan.inv_date` are set — matches trigger condition, prevents confusion.

---

## Sources

### Primary (HIGH confidence)
- Supabase pg_net docs — https://supabase.com/docs/guides/database/extensions/pg_net
- Supabase upsert reference — https://supabase.com/docs/reference/javascript/upsert
- Supabase PostgREST joins — https://supabase.com/docs/guides/database/joins-and-nesting
- Codebase: `borrower-portal/app/api/admin/transfer/route.ts` — service-role API pattern
- Codebase: `village-vista/app/api/sync-photos/route.ts` — CORS + external call pattern
- Codebase: `landflow/index.html` — CRM fetch pattern (`syncPhotosToWebsite`)
- Codebase: `borrower-portal/supabase/migrations/` — migration style, additive pattern
- Codebase: `borrower-portal/lib/types.ts` — existing Loan interface (no `hsf_loan` fields)
- Codebase: `borrower-portal/app/(admin)/admin/AdminDashboardClient.tsx` — loan list structure

### Secondary (MEDIUM confidence)
- Supabase pg_net is pre-installed on hosted projects — confirmed by multiple community sources and official Supabase changelog

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed; pg_net is built-in on Supabase hosted
- Architecture: HIGH — mirrors established patterns in existing codebase (transfer route, sync-photos, CRM fetch)
- Pitfalls: HIGH — sourced from direct codebase inspection and known pg_net/CORS gotchas
- Table design: HIGH — follows existing migration style exactly

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable tech; Supabase APIs change slowly)
