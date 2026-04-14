---
gsd_state_version: 1.0
milestone: v1.1
milestone_name: Tax Reporting & 1098s
status: roadmap_created
stopped_at: null
last_updated: "2026-04-08"
last_activity: 2026-04-08
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 0
  completed_plans: 0
  percent: 0
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-08)

**Core value:** Borrowers can access their annual 1098 tax form, and admin has an accountant-ready report for IRS filing.
**Current focus:** Roadmap created for milestone v1.1 — ready to plan Phase 06

## Current Position

Phase: HSF Phase 06 (next to plan)
Plan: —
Status: Roadmap created, awaiting phase planning
Last activity: 2026-04-08 — Roadmap created for v1.1 Tax Reporting & 1098s

Progress: [░░░░░░░░░░] 0%

## v1.1 Phase Summary

| Phase | Goal | Status |
|-------|------|--------|
| HSF 06: Data Foundation | TIN field, interest calc, eligibility rules | Not started |
| HSF 07: 1098 PDF Generation | Generate compliant Form 1098 PDFs | Not started |
| HSF 08: Portal & Admin Reporting | Borrower download + admin accountant report | Not started |
| HSF 09: Notifications | Admin-triggered January batch email | Not started |

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: --
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: --
- Trend: --

| Phase 01-crm-photo-management P01 | 10 | 1 tasks | 2 files |
| Phase 01-crm-photo-management P02 | 15 | 2 tasks | 1 files |
| Phase 02-photo-sync-engine P02 | 5 | 1 tasks | 1 files |
| Phase 02-photo-sync-engine P01 | 2 | 2 tasks | 2 files |
| Phase 01 P02 | 25 | 2 tasks | 10 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Fixed 7-photo formula: 2 parcel + 3 first stock + 2 random stock
- Admin video approval required (no auto-approve)
- Base64 vault storage stays as-is this milestone
- [Phase 01-crm-photo-management]: Stock photos fetched in a separate query after the main Promise.all to keep loadAllData lean (D-01, D-02)
- [Phase 01-crm-photo-management]: sort_order defaults to 0 so existing rows work without migration data
- [Phase 01-crm-photo-management]: No external drag-and-drop library — vanilla HTML5 drag events sufficient for a 13-item grid
- [Phase 01-crm-photo-management]: All sort_order values reindexed gaplessly on every drop so Phase 2 sync engine reads first 3 stock photos in correct user-defined order
- [Phase 02-photo-sync-engine]: Preserve emoji prefix in syncPhotosToWebsite() success toast to avoid visual regression
- [Phase 02-photo-sync-engine]: enhanceBuffer() omits .resize() to preserve portrait photo aspect ratios
- [Phase 02-photo-sync-engine]: Always upsert on upload; existence-check download removed as wasteful round-trip
- [Phase 02-photo-sync-engine]: Storage path always .jpg since enhanceBuffer outputs JPEG
- [Phase 01]: Use getClaims() as primary JWT role reader in middleware (with decodeJwt fallback) — cleaner and signature-validating vs raw cookie decode
- [Phase 01]: Root page.tsx redirects to /login — middleware handles role-based portal routing for authenticated users
- [v1.1 Roadmap]: Interest calculated from payment ledger (not amortization schedule) — DATA-02
- [v1.1 Roadmap]: Borrower TIN supports both SSN (masked to last 4) and EIN (full) — DOC-02
- [v1.1 Roadmap]: Lender EIN stored as LENDER_EIN env var — DOC-03
- [v1.1 Roadmap]: Portal link only in email, no PDF attachment (PII risk) — NOTIF-01
- [v1.1 Roadmap]: Admin must trigger batch email; no unsupervised auto-send — NOTIF-02
- [v1.1 Roadmap]: January cron mirrors existing payment-reminders pattern
- [v1.1 Roadmap]: PDF generation uses @react-pdf/renderer (server-side)

### Pending Todos

None yet.

### Blockers/Concerns

- Forte ACH sandbox credentials still pending (HSF v1.0 concern, not blocking v1.1)
- HSF Phase 05 (CRM Integration) must be complete before v1.1 phases can execute

## Session Continuity

Last session: 2026-04-08
Stopped at: Roadmap created for v1.1
Resume file: None
