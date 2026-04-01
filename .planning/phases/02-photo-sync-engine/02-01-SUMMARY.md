---
phase: 02-photo-sync-engine
plan: 01
subsystem: village-vista/sync-api
tags: [image-processing, sync, rls, sharp, supabase-storage]
dependency_graph:
  requires: [01-01, 01-02]
  provides: [SYNC-01, SYNC-02, SYNC-03, SYNC-05]
  affects: [village-vista/app/api/sync-photos/route.ts, village-vista/lib/pipeline/image-enhancer.ts]
tech_stack:
  added: []
  patterns: [buffer-in-buffer-out image enhancement, 7-photo formula assembly, service-role-key enforcement]
key_files:
  modified:
    - village-vista/lib/pipeline/image-enhancer.ts
    - village-vista/app/api/sync-photos/route.ts
decisions:
  - "enhanceBuffer() omits .resize() to preserve portrait photo aspect ratios (fit: inside recommended if resize needed later)"
  - "Always upsert on upload — existence check via .download() removed as wasteful round-trip"
  - "Storage path always uses .jpg extension since enhanceBuffer outputs JPEG"
metrics:
  duration: 2 minutes
  completed_date: "2026-04-01"
  tasks_completed: 2
  files_modified: 2
---

# Phase 02 Plan 01: 7-Photo Formula Sync Engine Summary

**One-liner:** Service-role-enforced sync route with Sharp buffer enhancement and 2-parcel + 3-first-stock + 2-random 7-photo formula ordered by sort_order ASC.

## What Was Built

### Task 1: enhanceBuffer() export (image-enhancer.ts)
Added a new exported async function `enhanceBuffer(input: Buffer, options?: EnhanceOptions): Promise<Buffer>` to the existing image enhancer module. The function takes a raw image buffer and returns an enhanced JPEG buffer using the same brightness/contrast/saturation/sharpness defaults as the file-path variant. No `.resize()` is applied — user-uploaded parcel photos may be portrait or square, and forced 1920x1080 resize would distort them.

**Commit:** `767cc99`

### Task 2: Rewrite sync-photos route (route.ts)
Rewrote the POST handler with five targeted changes:

1. **RLS fix (SYNC-03):** `getSupabase()` now throws `'SUPABASE_SERVICE_ROLE_KEY is required for vault_files access'` if the env var is absent. Silent fallback to anonKey is completely removed.

2. **Stock photo query fix (SYNC-01):** Changed `.order('created_at', ...)` to `.order('sort_order', { ascending: true })` and added `sort_order` to the select fields. This ensures Phase 1's drag-reorder ordering is honored.

3. **7-photo formula (SYNC-01, SYNC-02):** Replaced the naive "combine all photos" approach with:
   - `parcelSet`: up to 2 parcel photos (filtered to valid images)
   - `firstThreeStock`: first 3 from sort_order-ordered stock
   - `randomTwo`: 2 randomly shuffled from the remaining stock pool
   - `imageFiles = [...parcelSet, ...firstThreeStock, ...randomTwo]` — parcel first

4. **Enhancement (SYNC-05):** Each buffer is piped through `enhanceBuffer()` before upload. Enhancement failures are caught per-photo and fall back to the original buffer so one bad photo can't abort the entire sync.

5. **Anti-pattern removed:** The existence-check `.download(storagePath)` block is gone. Always upsert with the enhanced JPEG, storage path always ends in `.jpg`.

**Commit:** `b51d423`

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| No `.resize()` in `enhanceBuffer()` | User parcel photos may be portrait; 1920x1080 forced crop would be destructive |
| Remove existence-check download | Wasteful round-trip; always re-enhance and upsert ensures enhanced photos replace any unenhanced ones |
| Storage path always `.jpg` | Output of `enhanceBuffer()` is always JPEG regardless of input format |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all data paths are wired. The formula assembly and enhancement are complete and functional.

## Requirements Satisfied

| Req ID | Status |
|--------|--------|
| SYNC-01 | Done — 7-photo formula with sort_order ordering |
| SYNC-02 | Done — parcel photos at positions 1-2, stock at 3-7 |
| SYNC-03 | Done — throws on missing service role key, no silent fallback |
| SYNC-05 | Done — enhanceBuffer() called on each photo before upload |

## User Setup Required

`SUPABASE_SERVICE_ROLE_KEY` must be set in the Netlify dashboard for production:
- Source: Supabase Dashboard -> Settings -> API -> service_role key
- Target: Netlify Dashboard -> Site -> Environment variables -> SUPABASE_SERVICE_ROLE_KEY

Without this, the API will return a 500 error with a clear message (not silently process 0 photos).

## Self-Check: PASSED

- [x] `village-vista/lib/pipeline/image-enhancer.ts` — modified, `enhanceBuffer` export confirmed at line 50
- [x] `village-vista/app/api/sync-photos/route.ts` — modified, all acceptance criteria verified
- [x] Commit `767cc99` — confirmed in git log
- [x] Commit `b51d423` — confirmed in git log
- [x] `anonKey` — zero matches in route.ts
- [x] `.download(storagePath)` — zero matches in route.ts
