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

## v1.1 Requirements

Requirements for milestone v1.1: Tax Reporting & 1098s (HSF). Each maps to roadmap phases.

### Data Foundation

- [ ] **DATA-01**: Admin can enter a borrower's TIN (SSN or EIN) on the loan record
- [ ] **DATA-02**: System calculates annual interest received per loan from the payment ledger (not amortization schedule)
- [ ] **DATA-03**: Loans with $600+ interest received in a tax year are flagged as 1098-eligible (per loan, not per borrower)
- [ ] **DATA-04**: Paid-off loans that received $600+ interest during the tax year are included in 1098 generation

### Documents

- [ ] **DOC-01**: System generates an IRS Form 1098 (Copy B) PDF for each eligible loan
- [ ] **DOC-02**: 1098 PDF displays borrower TIN (SSN masked to last 4, EIN shown in full)
- [ ] **DOC-03**: 1098 PDF includes lender info (HSF name, address, EIN from env var)
- [ ] **DOC-04**: Interest is pro-rated for loans originated mid-year (Box 2 = original principal at origination)

### Portal & Reporting

- [ ] **PORT-01**: Borrower can view and download their 1098 PDF from the portal
- [ ] **PORT-02**: Admin can view an accountant summary report of all interest received per borrower for a tax year
- [ ] **PORT-03**: Admin sees pre-flight warnings for borrowers missing TIN before 1098 generation
- [ ] **PORT-04**: Admin report shows e-file threshold indicator (10+ forms = mandatory e-file)

### Notifications

- [ ] **NOTIF-01**: Automated January email notifies qualifying borrowers their 1098 is available (portal link, no PDF attachment)
- [ ] **NOTIF-02**: Admin triggers the batch email send (no unsupervised auto-send)

## v1.2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Tax Reporting

- **DOC-05**: CORRECTED 1098 checkbox and re-generation workflow
- **PORT-05**: Note buyer can generate 1098s for their own notes
- **DOC-06**: Box 8 APN fallback for vacant land parcels
- **DOC-07**: IRS e-filing via IRIS

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
| IRS e-filing (FIRE/IRIS) | Accountant handles manual filing; deferred to v1.2 |
| Note buyer 1098 generation | Deferred to v1.2 |
| CORRECTED 1098 re-generation | Deferred to v1.2; PDF template will include checkbox stub |
| Box 8 APN fallback for vacant land | Deferred to v1.2 |
| Auto-approving videos | Admin approval is intentional for quality control |
| Migrating vault base64 to Supabase Storage | Works currently, just inefficient; defer |
| LandID integration with CRM | Admin-only workflow is fine for now |
| Mobile app | Web-first |
| Two-way sync (HSF back to CRM) | One-way push is sufficient for now |
| Cron-based sync | Trigger is faster and more reliable |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

### v1.0 (Complete)

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

### v1.1 (Current)

| Requirement | Phase | Status |
|-------------|-------|--------|
| DATA-01 | HSF Phase 06 | Pending |
| DATA-02 | HSF Phase 06 | Pending |
| DATA-03 | HSF Phase 06 | Pending |
| DATA-04 | HSF Phase 06 | Pending |
| DOC-01 | HSF Phase 07 | Pending |
| DOC-02 | HSF Phase 07 | Pending |
| DOC-03 | HSF Phase 07 | Pending |
| DOC-04 | HSF Phase 07 | Pending |
| PORT-01 | HSF Phase 08 | Pending |
| PORT-02 | HSF Phase 08 | Pending |
| PORT-03 | HSF Phase 08 | Pending |
| PORT-04 | HSF Phase 08 | Pending |
| NOTIF-01 | HSF Phase 09 | Pending |
| NOTIF-02 | HSF Phase 09 | Pending |

**Coverage:**
- v1.1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-08 after milestone v1.1 roadmap creation*
