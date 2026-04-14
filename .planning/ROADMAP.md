# Roadmap: Photo-to-Video Pipeline Fix (v1.0)

## Overview

This milestone fixes the broken photo-to-video pipeline end-to-end. Starting from CRM photo management (previews and ordering), through the sync engine that assembles the 7-photo formula and pushes to the website, to the gallery display on property pages, and finally video generation with admin approval. Each phase builds on the previous, following the data flow from CRM to website.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: CRM Photo Management** - Fix stock and parcel photo previews and enable drag-reorder in the vault (completed 2026-04-01)
- [ ] **Phase 2: Photo Sync Engine** - Assemble 7-photo formula and reliably sync to website storage
- [ ] **Phase 3: Property Gallery** - Display synced photos in a carousel on property detail pages
- [ ] **Phase 4: Video Pipeline** - Generate videos from the synced photo set and route to admin approval

## Phase Details

### Phase 1: CRM Photo Management
**Goal**: Users can see and organize their photos in the CRM vault before syncing
**Depends on**: Nothing (first phase)
**Requirements**: PHOTO-01, PHOTO-02, PHOTO-03
**Success Criteria** (what must be TRUE):
  1. User opens the global stock photos section in the vault and sees image thumbnails (not just filenames)
  2. User can drag stock photos into a specific order, and that order persists after page reload
  3. User opens a loan's parcel photos folder and sees image thumbnails of uploaded parcel photos
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- Fix stock photo previews and add sort_order column
- [x] 01-02-PLAN.md -- Implement drag-reorder for stock photos and verify parcel previews

### Phase 2: Photo Sync Engine
**Goal**: The sync pipeline reliably assembles and delivers the correct 7-photo set to the website
**Depends on**: Phase 1
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04, SYNC-05
**Success Criteria** (what must be TRUE):
  1. After sync, the website's property-photos bucket contains exactly 7 photos: 2 parcel + 3 first stock + 2 random stock
  2. Parcel photos occupy positions 1-2 in the synced set, followed by stock photos in positions 3-7
  3. Sync completes without RLS permission errors when reading vault_files via service role key
  4. CRM displays a clear success or failure message after triggering photo sync
  5. Synced photos are auto-enhanced (brightness, contrast, saturation, sharpening) before uploading to Supabase Storage
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md -- Rewrite sync-photos route with 7-photo formula, RLS fix, and auto-enhancement
- [x] 02-02-PLAN.md -- Add loading state and error toasts to CRM sync button
- [ ] 02-03-PLAN.md -- Verify Netlify env var and end-to-end sync pipeline

### Phase 3: Property Gallery
**Goal**: Website visitors see property photos in an interactive carousel with correct ordering
**Depends on**: Phase 2
**Requirements**: GAL-01, GAL-02, GAL-03
**Success Criteria** (what must be TRUE):
  1. Property detail page shows a click-through photo carousel that visitors can navigate forward and back
  2. The first photos a visitor sees (hero/landing images) are the parcel-specific photos
  3. Scrolling through the carousel shows parcel photos first, then stock photos in order
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 03-01: TBD

### Phase 4: Video Pipeline
**Goal**: Videos are automatically generated from synced photos and queued for admin approval
**Depends on**: Phase 3
**Requirements**: VID-01, VID-02, VID-03, VID-04
**Success Criteria** (what must be TRUE):
  1. After a successful photo sync, video generation starts automatically without manual triggering
  2. The generated video uses the same 7 photos in the same order as the website gallery
  3. The completed video appears in the pending_videos table for admin review and approval
  4. If video generation fails (FFmpeg error, API timeout), the failure is logged and visible to the admin
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

---

## HSF Platform: Role Foundation & CRM Integration

### Phase 01: Role Foundation (borrower-portal)
**Goal**: RBAC infrastructure established — user_roles table, JWT hook, middleware, route groups — so admin, note_buyer, and borrower each access only their own area
**Depends on**: Nothing (first HSF phase)
**Requirements**: RBAC-01, RBAC-02, RBAC-03, RBAC-04, RBAC-05
**Success Criteria** (what must be TRUE):
  1. user_roles table exists with app_role enum (admin, note_buyer, borrower)
  2. JWT Custom Access Token Hook injects user_role claim at login
  3. Next.js middleware reads role from JWT claim (no DB call per request)
  4. Route groups /admin/*, /buyer/*, /(portal)/* are each protected by role check
  5. Admin user seeded via SQL migration and can log in
**Plans**: 2 plans

Plans:
- [x] 01-01-PLAN.md -- SQL migration: role enum, user_roles table, JWT hook, admin seed
- [x] 01-02-PLAN.md -- SSR upgrade, middleware RBAC, route group scaffolding

### Phase 05: CRM Integration
**Goal**: LandFlow CRM loan data syncs to HSF borrower-portal automatically via Postgres trigger, with manual fallback button and admin sync status visibility
**Depends on**: HSF Phase 01 (Role Foundation — admin role required for sync status view)
**Requirements**: CRM-01, CRM-02, CRM-03, CRM-04, CRM-05
**Success Criteria** (what must be TRUE):
  1. Setting nb_email and inv_date on a LandFlow loan causes a loan record to appear in HSF (auto-trigger)
  2. Clicking "Push to HSF" in LandFlow CRM creates or updates the correct loan record in HSF
  3. A sync with missing required fields fails validation and writes to hsf_sync_errors without corrupting data
  4. Admin can see sync status (last synced, error state) for each loan in the admin loan list
  5. Running the same sync twice for the same parcel does not create duplicate loans
**Plans**: 2 plans

Plans:
- [ ] 05-01-PLAN.md -- SQL migration (hsf_loans, hsf_sync_errors, pg_net trigger) + /api/crm-sync route
- [ ] 05-02-PLAN.md -- CRM "Push to HSF" button + admin sync status column

---

## HSF Platform: Tax Reporting & 1098s (v1.1)

**Milestone Goal:** Borrowers can access their annual 1098 tax form, and admin has an accountant-ready report for IRS filing.

### Phase 06: Data Foundation
**Goal**: The system can calculate annual interest per loan from actual payments, identify 1098-eligible loans, and store borrower TINs
**Depends on**: HSF Phase 05 (loan records must exist in HSF)
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04
**Success Criteria** (what must be TRUE):
  1. Admin can enter and save a borrower's TIN (SSN or EIN) on the loan record in the admin portal
  2. For any loan and tax year, the system produces a total of interest received calculated from actual payment ledger entries (not amortization)
  3. Loans with $600 or more in interest received for the year are marked as 1098-eligible; loans below that threshold are not
  4. A paid-off loan that received $600+ interest during the tax year appears in the eligible set alongside active loans
**Plans**: TBD

Plans:
- [ ] 06-01: TBD

### Phase 07: 1098 PDF Generation
**Goal**: The system generates a compliant IRS Form 1098 (Copy B) PDF for each eligible loan, with correct TIN masking, lender info, and pro-rated interest for mid-year originations
**Depends on**: Phase 06 (requires TIN and interest calculation)
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04
**Success Criteria** (what must be TRUE):
  1. For each eligible loan, the system produces a downloadable PDF that matches the IRS Form 1098 (Copy B) layout
  2. The PDF displays the borrower's SSN masked to the last 4 digits, or EIN shown in full
  3. The PDF shows the lender's name, address, and EIN pulled from the LENDER_EIN environment variable — not hardcoded
  4. For a loan originated mid-year, Box 1 shows only the interest received after the origination date, and Box 2 shows the original principal balance at origination
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 07-01: TBD

### Phase 08: Portal & Admin Reporting
**Goal**: Borrowers can download their 1098 from the portal, and admin has an accountant-ready summary report with pre-flight warnings before generation
**Depends on**: Phase 07 (PDFs must be generated before they can be viewed or reported)
**Requirements**: PORT-01, PORT-02, PORT-03, PORT-04
**Success Criteria** (what must be TRUE):
  1. A borrower logs into their portal and can view and download their 1098 PDF for the current tax year
  2. Admin opens the 1098 report page, selects a tax year, and sees a summary table of all interest received per borrower
  3. Before generating 1098s, admin sees a warning list of borrowers with missing TINs so no forms are generated with blank tax IDs
  4. The admin report shows a visible indicator when 10 or more forms are due, alerting the admin to the mandatory e-file threshold
**Plans**: TBD
**UI hint**: yes

Plans:
- [ ] 08-01: TBD

### Phase 09: Notifications
**Goal**: Qualifying borrowers receive an email in January notifying them their 1098 is available, triggered by admin (no unsupervised auto-send)
**Depends on**: Phase 08 (portal link must work before email is sent)
**Requirements**: NOTIF-01, NOTIF-02
**Success Criteria** (what must be TRUE):
  1. Admin opens the notifications panel, reviews the list of qualifying borrowers, and clicks "Send 1098 Emails" — each borrower receives an email with a portal link (no PDF attached)
  2. The email send cannot run without admin action — there is no automatic unsupervised batch send
  3. Borrowers who receive the email can click the portal link and land directly on their 1098 download page
**Plans**: TBD

Plans:
- [ ] 09-01: TBD

---

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 (v1.0), then HSF 01 -> HSF 05 -> HSF 06 -> HSF 07 -> HSF 08 -> HSF 09

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. CRM Photo Management | v1.0 | 2/2 | Complete | 2026-04-03 |
| 2. Photo Sync Engine | v1.0 | 0/3 | Planned | - |
| 3. Property Gallery | v1.0 | 0/0 | Not started | - |
| 4. Video Pipeline | v1.0 | 0/0 | Not started | - |
| HSF 01. Role Foundation | HSF v1.0 | 0/2 | Planned | - |
| HSF 05. CRM Integration | HSF v1.0 | 0/2 | Planned | - |
| HSF 06. Data Foundation | v1.1 | 0/0 | Not started | - |
| HSF 07. 1098 PDF Generation | v1.1 | 0/0 | Not started | - |
| HSF 08. Portal & Admin Reporting | v1.1 | 0/0 | Not started | - |
| HSF 09. Notifications | v1.1 | 0/0 | Not started | - |
