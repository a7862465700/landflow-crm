# Phase 01: Role Foundation - Validation Architecture

**Phase:** 01-role-foundation
**Created:** 2026-04-03
**Source:** Extracted from 01-RESEARCH.md Validation Architecture section

---

## Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected in project (vanilla JS SPA + Next.js site, no test config found) |
| Config file | None — Wave 0 must establish |
| Quick run command | `npx jest --testPathPattern=middleware --passWithNoTests` (after Wave 0) |
| Full suite command | `npx jest --passWithNoTests` |

---

## Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RBAC-01 | `user_roles` table has correct columns and enum | Manual (SQL inspect) | -- manual only | N/A |
| RBAC-02 | Hook injects `user_role` into JWT at login | Manual (decode JWT after login) | -- manual only | N/A |
| RBAC-03 | Middleware redirects borrower from `/admin` without DB call | Integration | `npx jest tests/middleware.test.ts -x` | Wave 0 |
| RBAC-04 | Admin visits `/admin` and sees admin layout; wrong-role redirected; admin/buyer blocked from borrower routes | E2E smoke | Manual browser test | N/A |
| RBAC-05 | Admin seed SQL inserts valid user who can log in | Manual (login attempt) | -- manual only | N/A |

**Manual-only justification:** SQL migration correctness, JWT claim injection via Supabase hook, and end-to-end login flow all require a live Supabase instance. Automated test coverage is realistic only for the middleware logic itself (unit-testable with mocked request/response).

---

## Sampling Rate

- **Per task commit:** `npx jest tests/middleware.test.ts --passWithNoTests`
- **Per wave merge:** `npx jest --passWithNoTests`
- **Phase gate:** Middleware unit tests green + manual JWT decode confirms `user_role` claim + manual login test with admin seed user

---

## Wave 0 Gaps

- [ ] `tests/middleware.test.ts` — unit test for middleware routing logic (mock getClaims/decodeJwt return)
- [ ] `jest.config.ts` or `jest.config.js` — project has no test framework configured
- [ ] `jest.setup.ts` — any shared test setup

---

## Verification Approach

Since the project has no test framework, phase 01 relies on:

1. **Build verification:** `npx next build` must pass with zero TypeScript errors
2. **Static analysis:** grep-based checks that middleware contains required patterns (ROLE_ROUTES, decodeJwt, getUser, borrower route entries)
3. **Manual JWT verification:** After hook enablement (Plan 01-01 Task 2), login as admin and decode the JWT in browser console to confirm `user_role` claim is present
4. **Manual route testing:** Visit /admin as admin (should see dashboard), visit /admin as borrower (should redirect to /dashboard), visit /dashboard as admin (should redirect to /admin)
