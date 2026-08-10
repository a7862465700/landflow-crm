# Hold harmless gate — spec for the HSF portal

The lender must accept a hold harmless agreement, signed with their typed name,
before they get access to anything in the Hickory Street Finance portal.

**This is portal work.** The gate lives in `borrower-portal` (a separate Next.js
app, not in this repo). The database side is done and described below, so the
portal change is a drop-in.

## Required behaviour

1. Lender is invited from LandFlow (`✉️ Invite to HSF`). The agreement is
   emailed with the invitation.
2. Lender clicks through, sets a password, signs in.
3. **First thing they see is the hold harmless page.** Not the notes list, not
   a dashboard — this is a gate, not a banner. Nothing else is reachable until
   it is signed.
4. They read it and **type their name** into a signature field. Accept stays
   disabled until the field is non-empty.
5. On accept, stamp all four columns (below) in one write, then let them in.
6. On every later sign-in, if `hold_harmless_accepted_at` is set for the
   current `hold_harmless_version`, skip the gate.

## Storage — already in place, nothing to add

All on `note_lenders`, keyed by the lender's email (lowercased), which is how
the portal already matches a lender to their record:

| Column | Purpose |
|---|---|
| `hold_harmless_accepted_at` | timestamptz — when they accepted |
| `hold_harmless_version` | text — which version they accepted (e.g. `2026-06-02`) |
| `hold_harmless_signed_name` | text — **the name they typed** |
| `hold_harmless_ip` | text — request IP, evidence of execution |

The first two already existed and are populated for 9 lenders. The last two were
added for this (`supabase-migration-hold-harmless-signature.sql`); both nullable,
so nothing existing breaks.

Version matters: bump `hold_harmless_version` when the agreement text changes and
the gate re-triggers for everyone, which is the point of storing it.

### Why not `servicing_agreements`

That table has the right shape (`signed_name`, `signed_at`, `ip_address`,
`user_agent`, `agreement_version`) and is empty, so it looks like the obvious
home. It is not: `loan_id` and `parcel_id` are both NOT NULL, making it strictly
per-note. The hold harmless is one-time per *lender*, before they have access to
any note at all. Keeping it on `note_lenders` also keeps it beside the two
columns that already track it.

## The bug this replaces

The lender information page currently reports **"accepted"** for a lender who has
never accepted — confirmed for `ana78investments@gmail.com`, whose
`hold_harmless_accepted_at` is null and who has never signed in
(`last_sign_in_at` null, `email_confirmed_at` null).

Likely cause, unconfirmed without the portal source: the agreement is emailed at
the moment the invite is sent, so "sent" and "accepted" coincide for every lender
who eventually accepts. If the page reads something invite-related rather than
`hold_harmless_accepted_at`, it would look correct for all nine lenders who did
accept and be wrong only for one who has not — which is exactly what we see.

Testable: any lender invited but not yet signed in should currently display as
accepted.

Whoever picks this up: check what that component reads. `hold_harmless_accepted_at`
is the only field that means accepted.

## Verifying it works

```sql
-- Should show the typed name, not just a timestamp
select email, hold_harmless_accepted_at, hold_harmless_version,
       hold_harmless_signed_name, hold_harmless_ip
from note_lenders
where hold_harmless_accepted_at is not null
order by hold_harmless_accepted_at desc;

-- Nobody should be able to reach the portal without a row here
select email from note_lenders where hold_harmless_accepted_at is null;
```

Historical note: the nine existing acceptances predate the signature field, so
`hold_harmless_signed_name` is null for all of them. Decide whether they are
re-prompted (bump the version) or grandfathered (leave them).
