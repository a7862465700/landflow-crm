# Roadmap: Photo-to-Video Pipeline Fix (v1.0)

## Overview

This milestone fixes the broken photo-to-video pipeline end-to-end. Starting from CRM photo management (previews and ordering), through the sync engine that assembles the 7-photo formula and pushes to the website, to the gallery display on property pages, and finally video generation with admin approval. Each phase builds on the previous, following the data flow from CRM to website.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (e.g., 2.1): Urgent insertions (marked with INSERTED)

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
- [ ] 02-01-PLAN.md -- Rewrite sync-photos route with 7-photo formula, RLS fix, and auto-enhancement
- [ ] 02-02-PLAN.md -- Add loading state and error toasts to CRM sync button
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

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. CRM Photo Management | 2/2 | Complete   | 2026-04-01 |
| 2. Photo Sync Engine | 0/3 | Planned | - |
| 3. Property Gallery | 0/0 | Not started | - |
| 4. Video Pipeline | 0/0 | Not started | - |
