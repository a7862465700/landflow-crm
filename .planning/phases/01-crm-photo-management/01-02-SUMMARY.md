---
phase: 01-crm-photo-management
plan: 02
subsystem: ui, database
tags: [drag-and-drop, sort-order, vault, stock-photos, parcel-photos, vanilla-js]

# Dependency graph
requires:
  - phase: 01-01-crm-photo-management
    provides: sort_order column on vault_files and stock photo base64 fetch
provides:
  - Draggable stock photo grid with cursor:grab styling
  - sort_order persistence via dbUpdateVaultFile on every drop
  - New uploads placed at end of sort order via maxOrder calculation
  - User-verified parcel photo thumbnails in loan detail view
affects:
  - photo-sync pipeline (Phase 2 can now read first 3 stock photos in user-defined order)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Vanilla JS HTML5 drag-and-drop: dragstart/dragover/drop/dragend handlers on inline event attributes"
    - "Batch sort_order update: reindex all items after reorder, await each dbUpdateVaultFile in a loop"
    - "maxOrder + 1 + loopIndex pattern for placing new uploads at the end of an ordered set"

key-files:
  created: []
  modified:
    - landflow/index.html

key-decisions:
  - "No external drag-and-drop library — vanilla HTML5 drag events sufficient for a 13-item grid"
  - "All sort_order values reindexed on every drop (not just swapped) to keep them gapless and predictable"
  - "New stock photo uploads assigned sort_order = maxOrder + 1 + loopIndex so multiple simultaneous uploads also stay in order"

patterns-established:
  - "Batch reindex pattern: splice to reorder in memory, then loop and await DB update for each item"

requirements-completed: [PHOTO-02, PHOTO-03]

# Metrics
duration: ~15min
completed: 2026-04-01
---

# Phase 1 Plan 02: Stock Photo Drag-and-Drop Reordering Summary

**Vanilla JS drag-and-drop reorder for 13 stock photos with gapless sort_order persistence and user-verified parcel photo thumbnails**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-01T00:00:00Z
- **Completed:** 2026-04-01T00:15:00Z
- **Tasks:** 2 (1 auto + 1 human-verify checkpoint)
- **Files modified:** 1

## Accomplishments

- Stock photo cards in the vault grid are now draggable (cursor:grab, opacity:0.4 during drag, ondragend reset)
- Dropping a card reorders the in-memory array, reindexes all sort_order values 0..N, persists each via dbUpdateVaultFile, and shows a "Photo order saved" toast
- New uploads via "Add Photos" are appended to the end using maxOrder + 1 + loopIndex so batch uploads also land in order
- User confirmed all 5 acceptance criteria in the live CRM: stock photo thumbnails render, drag reorder persists across reload, parcel photo thumbnails display, new uploads land at end, no console errors

## Task Commits

1. **Task 1: Implement drag-and-drop reordering for stock photos** - `e8d0d75` (feat)
2. **Task 2: Verify stock photo previews, drag-reorder, and parcel photo previews** - human-verify checkpoint, user approved

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `landflow/index.html` - Added stockDragStart/stockDragOver/stockDrop/dragend handlers; updated stock photo card div to include draggable="true", data-file-id, event attributes, cursor:grab; updated uploadGlobalStockPhoto to compute maxOrder and assign sort_order to new uploads

## Decisions Made

- Chose vanilla HTML5 drag-and-drop over a library — 13 items in a flat grid needs no additional abstraction
- Reindex all sort_order values after every drop (not a two-item swap) so the sequence stays gapless; this is the safest input for the Phase 2 sync engine which reads "first 3 by sort_order"
- New uploads use maxOrder + 1 + added (loop index) so a batch of multiple files also lands in deterministic order at the end

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. The sort_order column was added in Plan 01; no additional DB migrations are needed for this plan.

## Known Stubs

None — drag-and-drop is fully wired to dbUpdateVaultFile. sort_order values are persisted and re-read on renderVault(). No placeholder data flows to the UI.

## Next Phase Readiness

- Phase 01 is complete: all three PHOTO requirements satisfied (PHOTO-01 via Plan 01, PHOTO-02 and PHOTO-03 via this plan)
- Phase 02 sync engine can read `vaultFiles` sorted by sort_order and select the first 3 stock photos as the user intended
- No blockers for Phase 02

---
*Phase: 01-crm-photo-management*
*Completed: 2026-04-01*
