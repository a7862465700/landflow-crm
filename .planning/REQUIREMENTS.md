# Requirements: LandFlow CRM + Hot Springs Land Website

**Defined:** 2026-04-01
**Core Value:** When parcel photos are uploaded in the CRM, they appear on the correct property listing with a video — without manual intervention beyond admin video approval.

## v1.0 Requirements

Requirements for milestone v1.0: Photo-to-Video Pipeline Fix. Each maps to roadmap phases.

### CRM Photos

- [x] **PHOTO-01**: User can see image previews of global stock photos in the CRM vault
- [x] **PHOTO-02**: User can drag-reorder global stock photos to control which appear first
- [x] **PHOTO-03**: User can see image previews of parcel-specific photos in the CRM vault

### Sync

- [x] **SYNC-01**: Photo sync extracts exactly 2 parcel photos + 3 first stock + 2 random stock = 7 photos
- [x] **SYNC-02**: Parcel photos are positioned first in the synced set, stock photos follow
- [x] **SYNC-03**: Vault_files RLS bypass works reliably via service role key (no silent failures)
- [x] **SYNC-04**: Sync reports clear success/failure status back to the CRM
- [x] **SYNC-05**: Photos are auto-enhanced (brightness, contrast, saturation, sharpening) during sync using existing image-enhancer module

### Gallery

- [ ] **GAL-01**: Property detail page displays photos in a click-through carousel
- [ ] **GAL-02**: Parcel photos display as the hero/landing images on the property page
- [ ] **GAL-03**: Stock photos follow parcel photos in the carousel

### Video

- [ ] **VID-01**: Video generation auto-triggers after successful photo sync
- [ ] **VID-02**: Video uses the same 7-photo set in the same order as the website gallery
- [ ] **VID-03**: Generated video lands in pending_videos for admin approval
- [ ] **VID-04**: Video generation failures are logged and reported (not silent)

### CRM Integration (HSF)

- [ ] **CRM-01**: Setting nb_email and inv_date on a LandFlow parcel causes a loan record to appear in HSF within one trigger cycle (no manual action needed)
- [ ] **CRM-02**: Clicking "Push to HSF" in LandFlow CRM creates or updates the correct loan record in HSF
- [ ] **CRM-03**: A sync with missing required fields fails validation and writes a record to hsf_sync_errors without corrupting existing data
- [ ] **CRM-04**: Admin can see sync status (last synced, error state) for each loan in the admin loan list
- [ ] **CRM-05**: Running the same sync twice for the same parcel does not create duplicate loans

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### CRM Photos

- **PHOTO-04**: User can drag-reorder parcel-specific photos to pick which 2 and in what order

### Sync

- **SYNC-06**: Bulk re-sync all properties when global stock photos change

### Video

- **VID-05**: Admin can regenerate video for a property from the admin panel

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Auto-approving videos | Admin approval is intentional for quality control |
| Migrating vault base64 to Supabase Storage | Works currently, just inefficient; defer to future milestone |
| LandID integration with CRM | Admin-only workflow is fine for now |
| Mobile app | Web-first |
| Two-way sync (HSF back to CRM) | One-way push is sufficient for now |
| Cron-based sync | Trigger is faster and more reliable |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PHOTO-01 | Phase 1 | Complete |
| PHOTO-02 | Phase 1 | Complete |
| PHOTO-03 | Phase 1 | Complete |
| SYNC-01 | Phase 2 | Complete |
| SYNC-02 | Phase 2 | Complete |
| SYNC-03 | Phase 2 | Complete |
| SYNC-04 | Phase 2 | Complete |
| SYNC-05 | Phase 2 | Complete |
| GAL-01 | Phase 3 | Pending |
| GAL-02 | Phase 3 | Pending |
| GAL-03 | Phase 3 | Pending |
| VID-01 | Phase 4 | Pending |
| VID-02 | Phase 4 | Pending |
| VID-03 | Phase 4 | Pending |
| VID-04 | Phase 4 | Pending |
| CRM-01 | HSF Phase 05 | Pending |
| CRM-02 | HSF Phase 05 | Pending |
| CRM-03 | HSF Phase 05 | Pending |
| CRM-04 | HSF Phase 05 | Pending |
| CRM-05 | HSF Phase 05 | Pending |

**Coverage:**
- v1.0 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-04 after Phase 05 planning*
