---
phase: 01-role-foundation
plan: "02"
subsystem: borrower-portal
tags:
  - rbac
  - middleware
  - supabase-ssr
  - next.js
  - role-routing
dependency_graph:
  requires:
    - 01-01
  provides:
    - RBAC-03
    - RBAC-04
  affects:
    - borrower-portal/middleware.ts
    - borrower-portal/lib/supabase-server.ts
    - borrower-portal/app/auth/callback/route.ts
    - borrower-portal/app/(admin)
    - borrower-portal/app/(buyer)
tech_stack:
  added:
    - "@supabase/ssr@^0.10.0 (upgraded from ^0.4.0)"
    - "@supabase/supabase-js@^2.101.1 (upgraded from ^2.44.0)"
    - "jose@^6.2.2 (new — JWT decoding fallback)"
  patterns:
    - "getAll/setAll cookie API (replaced get/set/remove)"
    - "getClaims() for JWT claim reading (with decodeJwt fallback)"
    - "ROLE_ROUTES + ROLE_REDIRECT maps for role-based routing"
key_files:
  created:
    - "borrower-portal/app/(admin)/layout.tsx"
    - "borrower-portal/app/(admin)/admin/page.tsx"
    - "borrower-portal/app/(buyer)/layout.tsx"
    - "borrower-portal/app/(buyer)/buyer/page.tsx"
  modified:
    - "borrower-portal/middleware.ts"
    - "borrower-portal/lib/supabase-server.ts"
    - "borrower-portal/app/auth/callback/route.ts"
    - "borrower-portal/app/page.tsx"
    - "borrower-portal/package.json"
    - "borrower-portal/package-lock.json"
decisions:
  - "Use getClaims() (not raw cookie decode) as primary JWT claim reader since @supabase/auth-js 2.101.x exposes it — cleaner and signature-validating"
  - "Keep decodeJwt from jose as fallback path in case getClaims() throws, for forward-compatibility"
  - "Root page.tsx redirects to /login — middleware handles role-based portal routing for authenticated users"
metrics:
  duration: "~25 minutes"
  completed: "2026-04-03"
  tasks_completed: 2
  files_created: 4
  files_modified: 6
---

# Phase 01 Plan 02: Role-Based Middleware and Route Groups Summary

One-liner: JWT-claim role guard in Next.js middleware using getClaims() + ROLE_ROUTES map, with (admin) and (buyer) route group scaffolding alongside the existing (portal) borrower group.

## What Was Built

### Task 1 — Upgrade @supabase/ssr and rewrite middleware (commit: df14a24)

Upgraded the borrower-portal from `@supabase/ssr ^0.4.0` to `^0.10.0` (new cookie API), `@supabase/supabase-js ^2.44.0` to `^2.101.1`, and added `jose ^6.2.2`.

All three Supabase client files were updated from the old `get/set/remove` cookie API to the new `getAll/setAll` API:
- `lib/supabase-server.ts` — Server Component client
- `app/auth/callback/route.ts` — Auth exchange handler
- `middleware.ts` — Full rewrite with RBAC guard

The middleware now:
1. Calls `supabase.auth.getUser()` to validate the JWT (not `getSession()` — avoids the anti-pattern)
2. Reads `user_role` from `getClaims()` — no database call required
3. Falls back to `decodeJwt` on the raw access token cookie if `getClaims()` throws
4. Enforces `ROLE_ROUTES`: admin → `/admin`, note_buyer → `/buyer`, borrower → `/dashboard` + `/payments` + `/invoices` + `/statements` + `/contact`
5. On wrong-role access, redirects to the user's own portal (not a generic error page)
6. Preserves refreshed session cookies on all redirects by copying `supabaseResponse.cookies`

### Task 2 — Create (admin) and (buyer) route groups (commit: b011900)

Created Next.js route groups using parenthesis-excluded naming so group names don't appear in URLs:
- `app/(admin)/admin/page.tsx` → serves `/admin` URL with "Admin Dashboard" placeholder
- `app/(admin)/layout.tsx` → AdminLayout with HSF Admin sidebar
- `app/(buyer)/buyer/page.tsx` → serves `/buyer` URL with "Note Buyer Portal" placeholder
- `app/(buyer)/layout.tsx` → BuyerLayout with Note Buyer Portal sidebar
- `app/page.tsx` — updated to redirect to `/login` (was `/dashboard`)

The existing `(portal)` route group (borrower portal) was not modified.

## Verification

All acceptance criteria confirmed:
- `npx next build` passes in borrower-portal — 13 static pages, 0 TypeScript errors
- Routes `/admin` and `/buyer` appear in build output
- `middleware.ts` contains `getAll`, `ROLE_ROUTES`, `ROLE_REDIRECT`, `decodeJwt`, `getClaims`, `supabase.auth.getUser()`
- `/dashboard: 'borrower'` and all other borrower sub-routes present in `ROLE_ROUTES`
- `lib/supabase-server.ts` and `app/auth/callback/route.ts` both use `getAll/setAll`
- `app/(portal)/layout.tsx` unchanged (still uses Sidebar component)

## Deviations from Plan

### Auto-fix: Used getClaims() as primary JWT reader

The plan included a note that if `getClaims()` was available on the installed version, the executor MAY use it and remove the manual cookie/decode logic. Confirmed `getClaims()` is available in `@supabase/auth-js` 2.101.x. Used it as the primary approach with `decodeJwt` retained as a fallback (not removed entirely) — more resilient than pure fallback, cleaner than pure raw decode.

- **Type:** [Rule 2 — Enhancement] Cleaner JWT reading via getClaims()
- **Found during:** Task 1
- **Fix:** Used `supabase.auth.getClaims()` as primary, `decodeJwt` as catch fallback
- **Files modified:** `middleware.ts`
- **Commit:** df14a24

## Known Stubs

The admin and buyer placeholder pages contain stub copy ("coming soon" text). These are intentional — the plan explicitly calls them "placeholder pages." Future plans will replace these with real content.

- `app/(admin)/admin/page.tsx` — "Note management features coming soon." (intentional placeholder)
- `app/(buyer)/buyer/page.tsx` — "Purchased note features coming soon." (intentional placeholder)

## Self-Check: PASSED

Files confirmed to exist:
- borrower-portal/middleware.ts — FOUND (committed df14a24)
- borrower-portal/lib/supabase-server.ts — FOUND (committed df14a24)
- borrower-portal/app/auth/callback/route.ts — FOUND (committed df14a24)
- borrower-portal/app/(admin)/layout.tsx — FOUND (committed b011900)
- borrower-portal/app/(admin)/admin/page.tsx — FOUND (committed b011900)
- borrower-portal/app/(buyer)/layout.tsx — FOUND (committed b011900)
- borrower-portal/app/(buyer)/buyer/page.tsx — FOUND (committed b011900)

Commits verified:
- df14a24 — feat(01-02): upgrade @supabase/ssr and rewrite middleware with RBAC role guard
- b011900 — feat(01-02): create (admin) and (buyer) route groups with layouts and placeholder pages
