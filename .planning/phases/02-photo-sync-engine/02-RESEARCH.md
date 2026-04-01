# Phase 2: Photo Sync Engine - Research

**Researched:** 2026-04-01
**Domain:** Node.js image processing (Sharp), Supabase RLS bypass, Next.js API routes, vanilla JS feedback UI
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SYNC-01 | Photo sync extracts exactly 2 parcel photos + 3 first stock (by sort_order) + 2 random stock = 7 photos | Formula logic must be added in sync-photos/route.ts; sort_order column from Phase 1 drives correct ordering |
| SYNC-02 | Parcel photos are positioned first in the synced set, stock photos follow | Splice/concat strategy: build two arrays, concatenate in order before upload loop |
| SYNC-03 | Vault_files RLS bypass works reliably via service role key (no silent failures) | SUPABASE_SERVICE_ROLE_KEY is already in .env.local and already referenced in getSupabase() — needs the silent fallback removed; Netlify env var must be confirmed set |
| SYNC-04 | Sync reports clear success/failure status back to the CRM | CRM's syncPhotosToWebsite() currently shows toast on success but silently logs failure; needs showToast on error too, plus a loading state |
| SYNC-05 | Photos are auto-enhanced (brightness, contrast, saturation, sharpening) during sync using existing image-enhancer module | image-enhancer.ts takes file paths; must add a buffer-based variant; Sharp 0.34.5 is installed and accepts Buffer input confirmed locally |
</phase_requirements>

---

## Summary

Phase 2 modifies one file in each repo. On the website side (`village-vista/app/api/sync-photos/route.ts`), the existing POST handler must be updated to: enforce the service role key without fallback, apply the 7-photo formula (2 parcel + 3 first stock by sort_order + 2 random from remainder), and pipe each photo's buffer through image-enhancer logic before uploading to Supabase Storage. On the CRM side (`landflow/index.html`), the `syncPhotosToWebsite()` function needs a loading state and error-path toast.

The image-enhancer module (`lib/pipeline/image-enhancer.ts`) currently operates on file paths only. Since the sync pipeline works entirely in-memory with base64 buffers, a new buffer-based variant (or an in-place enhancement inline in the route) is needed. Sharp 0.34.5 (installed, confirmed) natively accepts `Buffer` and returns `Buffer` via `.toBuffer()`, making this straightforward.

The RLS situation is already partially addressed: `getSupabase()` in the current route does read `SUPABASE_SERVICE_ROLE_KEY`, and the key IS present in `.env.local`. The remaining risk is the silent fallback to `anonKey` when the env var is absent in Netlify's production environment. The fix is to throw an error (not silently continue) when the service key is missing.

**Primary recommendation:** Make all changes in the two existing files; no new files are required for SYNC-01 through SYNC-04. SYNC-05 needs either an inline buffer enhancement helper or a new exported function added to the existing `image-enhancer.ts`.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `sharp` | 0.34.5 (installed) | Image processing in-memory | Already in village-vista; used by LandID pipeline; accepts Buffer in, Buffer out |
| `@supabase/supabase-js` | ^2.44.0 (installed) | Supabase client (service role) | Already used throughout the website |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Next.js Route Handler | 14.2.5 | API endpoint | Already the mechanism in place |
| Vanilla JS `showToast` | n/a (CRM utility) | User feedback | Existing CRM pattern — use consistently |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Inline buffer enhancement in route.ts | Full refactor of image-enhancer.ts API | Refactor is cleaner long-term; inline is faster to ship. Recommend: add `enhanceBuffer()` to image-enhancer.ts. |
| Throwing on missing service key | Keeping silent fallback | Silent fallback caused SYNC-03. Remove it. |

**No new packages needed.** Sharp and Supabase are already installed and available.

---

## Architecture Patterns

### Files Changed

```
village-vista/
└── app/
    └── api/
        └── sync-photos/
            └── route.ts          # Main logic changes (SYNC-01, SYNC-02, SYNC-03, SYNC-05)
└── lib/
    └── pipeline/
        └── image-enhancer.ts     # Add enhanceBuffer() export (SYNC-05)

landflow/
└── landflow/
    └── index.html                # Update syncPhotosToWebsite() (SYNC-04)
```

### Pattern 1: Service Role Key Enforcement

**What:** Remove the silent fallback to anonKey in `getSupabase()`. Throw if the service key is missing.

**When to use:** Any server-side route that reads user-owned data (vault_files has `auth.uid() = user_id` RLS).

**Current (broken):**
```typescript
// Falls back silently — RLS will deny vault_files reads
return createClient(url, serviceKey || anonKey!);
```

**Fixed:**
```typescript
if (!serviceKey) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY is required for vault_files access');
}
return createClient(url, serviceKey);
```

### Pattern 2: 7-Photo Formula

**What:** Separate fetches for parcel and stock photos, then assemble the formula set.

**Logic:**
```typescript
// Parcel photos: take first 2 (ordered by created_at ASC)
const parcelSet = (parcelPhotos || []).slice(0, 2);

// Stock photos: ordered by sort_order ASC (Phase 1 guarantee)
// Take first 3 as "curated" set
const firstThreeStock = (stockPhotos || []).slice(0, 3);

// Remaining stock: shuffle, take 2 random
const remainingStock = (stockPhotos || []).slice(3);
const shuffled = remainingStock.sort(() => Math.random() - 0.5);
const randomTwo = shuffled.slice(0, 2);

// Final ordered set: parcel first, then stock
const photoSet = [...parcelSet, ...firstThreeStock, ...randomTwo];
// photoSet.length will be <= 7; may be fewer if not enough photos available
```

**Key detail:** The stock photo query must use `.order('sort_order', { ascending: true })` — the current code uses `created_at` which is WRONG for stock photos (Phase 1 added `sort_order` specifically for this).

### Pattern 3: Buffer-Based Image Enhancement

**What:** Enhance a base64 image buffer in-memory before uploading to Supabase Storage. No temp files.

**Add to `image-enhancer.ts`:**
```typescript
// Source: Sharp docs — accepts Buffer input, returns Buffer via .toBuffer()
export async function enhanceBuffer(
  input: Buffer,
  options?: EnhanceOptions
): Promise<Buffer> {
  const opts = { ...DEFAULTS, ...options };
  return sharp(input)
    .modulate({
      brightness: opts.brightness,
      saturation: opts.saturation,
    })
    .linear(opts.contrast, -(128 * (opts.contrast - 1)))
    .sharpen({ sigma: opts.sharpness })
    .toFormat('jpeg')
    .toBuffer();
}
```

**In sync-photos/route.ts** — call `enhanceBuffer(buffer)` right before the Supabase storage upload. Replace the raw `buffer` with the enhanced result.

**Note on resize:** The existing `enhanceScreenshots()` resizes to 1920x1080. For user-uploaded parcel photos, forced resize to 1920x1080 may distort portrait or non-landscape images. Recommend: omit the `.resize()` call in `enhanceBuffer()` for this phase, or use `fit: 'inside'` to avoid cropping. This is a Claude's Discretion area.

### Pattern 4: CRM Sync Button Feedback

**What:** The current `syncPhotosToWebsite()` shows a success toast but swallows errors silently (`console.warn` / `console.error` only).

**Fixed pattern:**
```javascript
async function syncPhotosToWebsite(loanId) {
  showToast('Syncing photos…');  // loading indicator
  try {
    const res = await fetch(VILLAGE_VISTA_API + '/api/sync-photos', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ loanId }),
    });
    const result = await res.json();
    if (result.success) {
      showToast('Photos synced to website (' + result.photosProcessed + ')', 'success');
    } else {
      showToast('Sync failed: ' + (result.error || 'Unknown error'), 'error');
    }
  } catch (err) {
    showToast('Sync failed: ' + (err.message || 'Network error'), 'error');
  }
}
```

**Note:** The CRM `showToast` signature is `showToast(message, type?)`. The second argument is optional; 'success' renders green, 'error' renders red.

### Anti-Patterns to Avoid

- **Using `.order('created_at')` for stock photos:** Phase 1 established `sort_order` as the canonical ordering column. Using `created_at` gives wrong order.
- **Silently continuing when service key is absent:** This hides the RLS error and makes sync appear to work while actually uploading zero photos.
- **Checking file existence before upload by attempting `.download()`:** The current code does this — it's a wasted network round-trip. Use `upsert: true` on upload instead (already used for new uploads).
- **Resizing parcel photos to 1920x1080 with `fit: 'cover'`:** Will crop portrait photos. Use `fit: 'inside'` or skip resize.
- **Triggering video generation immediately after sync:** This is currently fire-and-forget in the route. Keep it that way for now; Phase 4 will address proper video pipeline wiring.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Image brightness/contrast/sharpness | Custom pixel math | `sharp` `.modulate()`, `.linear()`, `.sharpen()` | Sharp handles all color models, bit depths, and EXIF data correctly |
| Random selection from array | Custom shuffle | `array.sort(() => Math.random() - 0.5).slice(0, 2)` | Sufficient for 2-from-10 selection at this scale |
| RLS bypass | Custom JWT logic | `SUPABASE_SERVICE_ROLE_KEY` with `createClient` | Service role key is the Supabase-blessed pattern; no custom auth needed |

---

## Common Pitfalls

### Pitfall 1: Stock Photos Queried in Wrong Order

**What goes wrong:** Sync delivers the wrong 3 "curated" stock photos because they're ordered by `created_at` instead of `sort_order`.

**Why it happens:** The current `route.ts` uses `.order('created_at', { ascending: true })` for stock photos. Phase 1 added `sort_order` but the sync route was not updated.

**How to avoid:** Change the stock photos query to `.order('sort_order', { ascending: true })`.

**Warning signs:** After sync, the "first 3" stock photos don't match what the user arranged via drag-reorder.

### Pitfall 2: Service Role Key Not Set in Netlify Production

**What goes wrong:** Sync works in local dev (where `.env.local` has the key) but fails in production with 0 photos processed — no error surfaced to the user.

**Why it happens:** Netlify environment variables must be set separately in the Netlify dashboard. The `.env.local` file is not deployed.

**How to avoid:** The plan must include a verification step: confirm `SUPABASE_SERVICE_ROLE_KEY` is set in the Netlify dashboard for the village-vista site. After removing the silent fallback, a missing key will throw immediately and surface as a 500 error with a clear message.

**Warning signs:** Sync returns `{ success: true, photosProcessed: 0 }` in production.

### Pitfall 3: Sharp Buffer Input Fails on Non-Standard Base64

**What goes wrong:** Sharp throws `Input file is missing` or `Input Buffer is empty` when given a malformed or empty base64 string.

**Why it happens:** vault_files stores photos as full data URIs (`data:image/jpeg;base64,...`). The base64 content must be extracted before passing to Sharp — the data URI prefix cannot be passed directly to `Buffer.from(str, 'base64')`.

**How to avoid:** The existing code already strips the prefix with a regex match. Ensure this extraction step runs before the Sharp call. Wrap Sharp processing in a try/catch per-photo so one bad photo doesn't abort the entire sync.

**Warning signs:** Sync completes with fewer than expected photos; server logs show Sharp errors on specific file IDs.

### Pitfall 4: CRM Shows No Feedback During Slow Sync

**What goes wrong:** User clicks sync, nothing happens visibly for several seconds (photo enhancement + upload is slow), user clicks again.

**Why it happens:** The current `syncPhotosToWebsite()` shows nothing until the response arrives.

**How to avoid:** Show a loading toast (`showToast('Syncing photos…')`) before the `fetch` call. The existing `showToast` utility supports this pattern.

### Pitfall 5: Photo Count May Be Less Than 7

**What goes wrong:** If a loan has fewer than 2 parcel photos, or there are fewer than 5 stock photos, the formula produces fewer than 7 photos. This is not an error — it's expected behavior.

**Why it happens:** Users may not have uploaded parcel photos yet; or the remaining stock pool (after taking first 3) has fewer than 2 photos.

**How to avoid:** The formula should take "up to" 2 parcel, "up to" 3 first stock, "up to" 2 random — using `.slice()` naturally handles this. Do not throw an error if the count is less than 7. Log the actual count in the response.

---

## Code Examples

### Verified: Sharp Buffer Pipeline (Sharp 0.34.5, confirmed installed)

```typescript
// Buffer in → Buffer out, no temp files needed
const enhanced = await sharp(inputBuffer)
  .modulate({ brightness: 1.1, saturation: 1.2 })
  .linear(1.15, -(128 * (1.15 - 1)))
  .sharpen({ sigma: 0.5 })
  .toFormat('jpeg')
  .toBuffer();
```

### Verified: Supabase Service Role Client

```typescript
// Correct pattern — throws rather than falls back
function getSupabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error('SUPABASE_SERVICE_ROLE_KEY is required');
  return createClient(url, key);
}
```

### Verified: Stock Photo Query with sort_order

```typescript
const { data: stockPhotos } = await supabase
  .from('vault_files')
  .select('id, data, name, type')
  .is('loan_id', null)
  .eq('cat_id', 'stock_photos')
  .order('sort_order', { ascending: true });  // Phase 1 column
```

### Verified: CRM showToast Pattern

```javascript
// CRM showToast signature: showToast(message, type?)
// type: 'success' (green), 'error' (red), undefined (neutral)
showToast('Syncing photos…');                         // loading, no type
showToast('Photos synced (7)', 'success');            // green
showToast('Sync failed: RLS denied', 'error');        // red
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `sharp` | SYNC-05 image enhancement | Yes | 0.34.5 | None needed |
| `@supabase/supabase-js` | SYNC-01/02/03 | Yes | ^2.44.0 | None needed |
| `SUPABASE_SERVICE_ROLE_KEY` in `.env.local` | SYNC-03 (local dev) | Yes | — | — |
| `SUPABASE_SERVICE_ROLE_KEY` in Netlify dashboard | SYNC-03 (production) | **UNKNOWN — must verify** | — | None — blocks production |
| Node.js | village-vista server | Yes | v24.14.0 | — |

**Missing dependencies with no fallback:**

- `SUPABASE_SERVICE_ROLE_KEY` in Netlify production dashboard: Must be verified/set. The plan must include a manual verification step before the phase is considered complete.

---

## Validation Architecture

> `workflow.nyquist_validation` is not set in config.json — treated as enabled.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None detected in either repo |
| Config file | None — Wave 0 gap |
| Quick run command | Manual: trigger sync from CRM and inspect response |
| Full suite command | Manual end-to-end: upload photo → sync → verify Supabase Storage contains 7 enhanced files |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SYNC-01 | Exactly 2 parcel + 3 first stock + 2 random stock in photoSet | Manual inspection of API response `photosProcessed` and `photoUrls` array | n/a | n/a |
| SYNC-02 | First 2 URLs in response are parcel photos, next 5 are stock | Manual: compare URL filenames against vault_files IDs | n/a | n/a |
| SYNC-03 | No RLS error; sync succeeds when called cross-origin from CRM | Manual: call sync from deployed CRM against production website | n/a | n/a |
| SYNC-04 | CRM shows toast with count on success, toast with error message on failure | Manual: trigger sync, observe toast | n/a | n/a |
| SYNC-05 | Uploaded photos are visually enhanced (brighter, more contrast) vs. originals | Manual: compare original base64 vs. Storage URL in browser | n/a | n/a |

**Note:** Neither repo has a test framework. No automated tests are feasible for this phase without first adding one. All validation is manual and observable.

### Wave 0 Gaps

- No test framework exists in either repo. For this phase, validation is entirely manual:
  1. Deploy village-vista to Netlify
  2. Confirm `SUPABASE_SERVICE_ROLE_KEY` is set in Netlify dashboard
  3. Trigger sync from CRM for a loan with parcel photos
  4. Check Supabase Storage `property-photos/<parcel>/` for 7 files
  5. Compare an enhanced file visually against the original base64 in vault_files

---

## Open Questions

1. **Resize behavior for parcel photos during enhancement**
   - What we know: The existing `enhanceScreenshots()` resizes to 1920x1080 with `fit: 'cover'` (crops). LandID screenshots are always landscape, so this is fine there.
   - What's unclear: User-uploaded parcel photos may be portrait or square. Cropping to 1920x1080 would be destructive.
   - Recommendation: In `enhanceBuffer()`, omit `.resize()` entirely. Keep the same brightness/contrast/saturation/sharpness settings. If resizing is desired later, use `fit: 'inside'` with a max-width constraint rather than `fit: 'cover'`.

2. **SUPABASE_SERVICE_ROLE_KEY in Netlify production**
   - What we know: It exists in `.env.local` locally. The website is deployed to Netlify.
   - What's unclear: Whether it's set in the Netlify dashboard for production. This cannot be verified without Netlify dashboard access.
   - Recommendation: Plan must include a manual step to confirm/set this env var in Netlify before testing production.

3. **"Existing file" check in storage**
   - What we know: The current code does a `.download()` to check if a file exists before uploading — a wasteful round-trip.
   - What's unclear: Since we're always enhancing and re-uploading, should we always upsert (skip the existence check entirely)?
   - Recommendation: Remove the existence-check download. Always enhance and upsert. This ensures enhanced photos replace any unenhanced ones from previous syncs. Use `upsert: true` (already present in the upload call).

---

## Sources

### Primary (HIGH confidence)

- Sharp 0.34.5 — verified via `node -e "require('sharp').versions"` in village-vista directory; Buffer input/output confirmed via `sharp(Buffer).toBuffer()` test
- `village-vista/app/api/sync-photos/route.ts` — read directly, line-by-line analysis
- `village-vista/lib/pipeline/image-enhancer.ts` — read directly
- `landflow/landflow/index.html` — syncPhotosToWebsite() function read directly (lines 956-972)
- `.env.local` in village-vista — SUPABASE_SERVICE_ROLE_KEY presence confirmed
- `.planning/REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `PROJECT.md`, `codebase/ARCHITECTURE.md`, `codebase/STACK.md` — all read directly

### Secondary (MEDIUM confidence)

- Sharp API documentation (buffer pipeline, modulate, linear, sharpen methods) — verified by direct API method introspection on installed package

### Tertiary (LOW confidence)

- None.

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — all packages are installed and verified locally
- Architecture: HIGH — all source files read directly; no inference required
- Pitfalls: HIGH — derived from direct code reading (wrong order column, silent fallback) and Sharp behavior verification
- Netlify env var status: LOW — cannot verify production dashboard remotely

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable stack, no fast-moving dependencies)
