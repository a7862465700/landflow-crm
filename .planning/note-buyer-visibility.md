# Note-buyer / HSF portal visibility — architecture & gotchas

Durable notes for Claude Code and the team when working on investor /
note-buyer visibility in this repo. (Root `CLAUDE.md` is gitignored via
`*.md`; tracked docs live under `.planning/`.)

## What this repo is

`landflow/index.html` (also mirrored at `landflow-index.html`) is a single-file
admin CRM for seller-financed vacant-land loans ("notes"). It talks directly to
a shared **Supabase** project (`Land Flow CRM`, ref `rcidwqyrrfrthujymncn`) that
is also used by the Village Vista website and the **Hickory Street Finance (HSF)**
note-buyer portal.

- Supabase schema seed: `supabase-setup.sql`.
- Most triggers, functions, and RLS policies were applied **directly to Supabase**
  and are **not fully version-controlled**. When you change DB objects, also add a
  `supabase-migration-*.sql` file to the repo as the source-of-truth record.
- `netlify/` holds serverless functions; deploy is via Netlify (`netlify.toml`).

## Actors & roles (`user_roles.role`, enum `app_role`)

- **admin** — the CRM operator. Sees everything.
- **note_buyer** — an investor who bought a note. Signs into the **HSF portal**
  (hickorystreetfinance.com, a separate Next.js app called `borrower-portal`,
  NOT in this repo) to view the notes they own and their payments.
- **borrower** — the buyer paying off a note. Has their own portal view.

## Note-buyer ("investor") data model — read this before touching visibility

An investor / note buyer is called several things across the code:
`investor` (legacy free-text field on `loans`), "note buyer" (`nb_*` fields), and
"lender". The canonical record is **`note_lenders`** (keyed by lowercased `email`),
synced to HSF. The CRM writes it via `dbSaveInvestor` (UPSERT on email).

Two distinct data paths expose notes to a logged-in note buyer, gated by
Supabase **RLS** using the buyer's own JWT (not a service-role bypass):

1. **`hsf_loans`** — the note-buyer-facing notes list. Synced from `loans` by the
   `trigger_crm_sync_to_hsf()` trigger (fires when `nb_email`/`inv_date` change)
   which POSTs `crm_loan_id` to HSF's `/api/crm-sync`. Matched to the buyer by
   **`nb_email`** (email-scoped RLS, like `note_lenders`).
2. **`loans` / `payments` / `late_fees`** — matched to the buyer by
   **`buyer_user_id`** (a uid FK), stamped by the `autolink_loan_to_buyer()`
   trigger which resolves `nb_email` → the `note_buyer` auth account.

Both paths must agree for a buyer to see notes AND their payment history.

### RLS gotchas (learned the hard way — see PR #29)

- **Every note-buyer-facing table needs an explicit note_buyer SELECT policy.**
  `hsf_loans` originally had only *admin* policies, so RLS returned **0 rows** for
  every note buyer — they logged in and saw nothing. Fixed by adding
  `"Note buyer reads own hsf_loans"`: `lower(nb_email) = lower(auth.jwt()->>'email')`,
  mirroring `"Note buyer reads own note_lenders"`.
- **`loans.buyer_user_id` must be re-resolved when `nb_email` changes.** The old
  `autolink_loan_to_buyer()` only set it when NULL, so reassigning a note to a new
  buyer left the *previous* buyer's uid in place → new buyer saw nothing and the
  previous buyer kept access to the note + payments (**cross-account leak**). The
  function now re-resolves on `nb_email` change and clears the link when the note
  is unassigned. Migration: `supabase-migration-note-buyer-visibility.sql`.
- When email is entered in the CRM, `note_lenders.email` / auth emails are
  **lowercased**, but `loans.nb_email` is only `.trim()`ed. Always compare emails
  case-insensitively (`lower(trim(...))`) in RLS and joins.
- To debug "investor can't see X", simulate their session in SQL:
  `set_config('role','authenticated',true)` +
  `set_config('request.jwt.claims', json_build_object('role','authenticated','email','<email>')::text, true)`
  then `select count(*) from <table>` inside a `begin; ... rollback;`.

## HSF sync (this repo → HSF portal)

- `pushToHSF(loanId)` → `POST https://hickorystreetfinance.com/api/crm-sync`
  (Bearer `HSF_SYNC_SECRET`) copies a loan into `hsf_loans`.
- `inviteNoteBuyerToHSF()` → `POST /api/admin/invite-lender` invites a lender to
  sign into the portal with the exact email on their PaperStack assignment letter.
- DB helpers: `sync_note_lender_to_hsf_loans`, `pull_note_lender_into_hsf_loans`,
  `transfer_note`. Tables: `hsf_loans`, `hsf_note_transfers`, `hsf_sync_errors`.
- Wrap notes (`note_type = 'wrap'`) are intentionally **never** synced to
  `hsf_loans` (buyer isolation).

## Conventions

- Prefer editing DB objects via a committed `supabase-migration-*.sql` file AND
  applying it to Supabase; keep the two in sync.
- Keep RLS additive and email/uid comparisons case-insensitive.
- Do not hand-edit generated mirrors; `landflow/index.html` is the app entry.
