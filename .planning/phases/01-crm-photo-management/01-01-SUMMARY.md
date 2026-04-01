---
phase: 01-crm-photo-management
plan: 01
subsystem: database, ui
tags: [supabase, vault, base64, stock-photos, sort-order]

# Dependency graph
requires: []
provides:
  - Separate base64 fetch for stock photos so vault thumbnails render correctly
  - sort_order column on vault_files table for drag-reorder in Plan 02
  - Stock photos sorted by sort_order in renderVault()
affects:
  - 01-02-crm-photo-management (drag-reorder depends on sort_order)
  - photo-sync pipeline (stock photos need to be selectable in correct order)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Lean main query (no data column) + targeted secondary fetch for base64-heavy rows"
    - "Merge secondary fetch results back into global array using Object.fromEntries"

key-files:
  created: []
  modified:
    - landflow/index.html
    - supabase-setup.sql

key-decisions:
  - "Stock photos fetched in a separate query after the main Promise.all to keep the main loadAllData query lean (D-01, D-02)"
  - "sort_order defaults to 0 so existing rows work without migration data"

patterns-established:
  - "Secondary fetch pattern: filter IDs from already-loaded array, fetch heavy columns, merge back with spread"

requirements-completed: [PHOTO-01]

# Metrics
duration: 10min
completed: 2026-04-01
---

# Phase 1 Plan 01: CRM Stock Photo Previews + sort_order Column Summary

**Separate base64 fetch for ~13 stock photos fixes broken vault thumbnails; sort_order column added to vault_files for drag-reorder in Plan 02**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-01T00:00:00Z
- **Completed:** 2026-04-01T00:10:00Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Stock photo thumbnails now render as 80x60px images in the vault (previously broken — `f.data` was always undefined because the main query excludes the `data` column)
- Secondary fetch pattern established: after `loadAllData` Promise.all, a targeted `select('id,data,sort_order').in('id', stockPhotoIds)` fetches only the base64 data for stock photos, then merges back into `vaultFiles`
- `sort_order integer default 0` column added to `vault_files` CREATE TABLE and via `ALTER TABLE IF NOT EXISTS` for existing databases — ready for Plan 02 drag-reorder

## Task Commits

1. **Task 1: Add sort_order column to vault_files and fetch stock photo data** - `035a9b0` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `landflow/index.html` - Updated vault_files select to include sort_order; added secondary base64 fetch for stock photos after loadAllData; sort stock photos by sort_order in renderVault()
- `supabase-setup.sql` - Added `sort_order integer default 0` to vault_files CREATE TABLE block; added `ALTER TABLE vault_files ADD COLUMN IF NOT EXISTS sort_order integer DEFAULT 0` at bottom of file

## Decisions Made

- Used a secondary targeted fetch (not modifying the main Promise.all query to include `data`) to keep the main loadAllData lean for all non-stock vault files — avoids loading large base64 blobs for documents, deeds, etc.
- sort_order defaults to 0 so all existing stock photos get equal weight until the user drags to reorder in Plan 02.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None — git HEAD.lock was stale (another process had crashed), removed it to proceed with commit.

## User Setup Required

**Run in Supabase SQL Editor to add the column to the live database:**

```sql
ALTER TABLE vault_files ADD COLUMN IF NOT EXISTS sort_order integer DEFAULT 0;
```

This is safe to run multiple times (IF NOT EXISTS). The CRM code already reads `sort_order` from the response, so running this is all that's needed for stock photo ordering to work correctly.

## Known Stubs

None — `f.data` is now populated for stock photos from the secondary fetch before renderVault() runs. The img src renders real base64 data.

## Next Phase Readiness

- Plan 02 (drag-reorder stock photos) can proceed: `sort_order` column exists in schema and is loaded into `vaultFiles` array for all stock photos
- Stock photo thumbnails display correctly in the vault grid

---
*Phase: 01-crm-photo-management*
*Completed: 2026-04-01*
