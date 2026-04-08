# Feature Research

**Domain:** IRS Form 1098 Tax Reporting — Owner-Finance Loan Servicing Platform (HSF)
**Researched:** 2026-04-08
**Confidence:** HIGH (IRS requirements sourced directly from IRS.gov; platform UX from industry survey)

---

## IRS Form 1098 Requirements Reference

Before the feature table, here are the hard constraints that drive every feature decision:

### Required Form Fields (Copy B — furnished to borrower)

| Box | Field | Notes |
|-----|-------|-------|
| Box 1 | Mortgage Interest Received | Total interest paid by borrower in the tax year — the primary reportable figure |
| Box 2 | Outstanding Mortgage Principal | Principal balance as of Jan 1 of the tax year (or origination date if mid-year) |
| Box 3 | Mortgage Origination Date | Date the note was originated |
| Box 4 | Refund of Overpaid Interest | Only if lender refunded interest previously collected |
| Box 5 | Mortgage Insurance Premiums | Leave blank — HSF notes don't carry MI |
| Box 6 | Points Paid | Leave blank — not applicable to owner-finance land notes |
| Box 7/8 | Address of Property Securing Mortgage | Parcel address or legal description |
| Box 9 | Number of Mortgaged Properties | 1 (each note is one property) |
| Box 10 | Other | Property taxes, etc. — leave blank unless applicable |
| Box 11 | Mortgage Acquisition Date | Leave blank unless note was acquired (transferred servicer) |

**Lender info required on form:** Name, address, TIN (EIN or SSN), phone number
**Borrower info required on form:** Name, address, TIN (SSN) — last 4 digits acceptable on Copy B

### Deadlines (for tax year 2025, filed in 2026)

| Action | Deadline |
|--------|----------|
| Furnish Copy B to borrower | January 31, 2026 |
| File paper Copy A with IRS | March 2, 2026 |
| File electronic Copy A with IRS | March 31, 2026 |

### Filing Threshold

- $600 minimum interest per mortgage per year — below this, no Form 1098 required
- Threshold applies per mortgage, not per borrower (if one borrower has two notes, each is evaluated separately)
- HSF is in the business of owner-finance lending, so the trade-or-business requirement is met

### E-Filing Requirement

- Aggregate 10+ information returns of any type (1098 + 1099s combined) = mandatory e-filing
- Fewer than 10 total = paper filing permitted
- HSF currently has a small portfolio; paper or manual e-file by accountant is sufficient (IRS e-filing out of scope per PROJECT.md)

### Pro-Rata / Mid-Year Interest

- Report only interest actually received during the tax year
- For loans originated mid-year: Box 1 = interest received from origination date through Dec 31
- Box 2 = principal as of origination date (not Jan 1) for first-year notes
- For paid-off notes: Box 1 = interest received Jan 1 through payoff date; form still required if $600+ was collected

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that borrowers and accountants assume exist. Missing these = the platform feels unfinished.

| Feature | Why Expected | Complexity | Dependencies |
|---------|--------------|------------|--------------|
| Annual interest calculation per loan | Core of 1098 — sum all interest payments in the tax year from the payment ledger | LOW | Requires payment ledger with interest/principal split per payment |
| $600 threshold filter | IRS requirement — do not generate 1098 for sub-threshold loans | LOW | Requires annual interest calculation |
| Generate 1098 PDF per borrower | Borrowers expect a downloadable tax form, not a raw data table | MEDIUM | Requires interest calc, borrower TIN, lender EIN, property address |
| Borrower portal: view and download 1098 | Borrowers expect self-service access; calling in for a tax form is a support burden | LOW | Requires PDF generation, Supabase Storage or on-demand generation |
| Automated January email to qualifying borrowers | Standard practice — borrowers expect the form delivered, not just available | MEDIUM | Requires pg_cron scheduled job, Resend email, 1098 PDF generation |
| Admin: accountant summary report | Accountant needs a single-view reconciliation of all interest received across all loans | MEDIUM | Requires annual interest calc per loan, borrower TIN, loan identifiers |
| Paid-off notes included for the active year | Borrowers who paid off mid-year still paid interest — they need the form | LOW | Requires filtering loans by activity in the tax year, not just current active loans |
| Mid-year origination pro-rata handling | IRS requires Box 2 principal as of origination date on first-year loans | LOW | Requires origination date from loan record |
| Borrower TIN capture/storage | Required on the 1098 form | MEDIUM | Requires data model addition; borrowers may need to self-submit via portal or admin enters it |

### Differentiators (Competitive Advantage)

Features that go beyond the minimum and add real value to admin or borrower experience.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| On-demand PDF generation (no pre-storage) | Admin can regenerate a 1098 any time without worrying about stale stored files | MEDIUM | Generate at request time from live payment data; avoids storage management headaches |
| Tax year selector in borrower portal | Borrower can pull prior-year 1098s, not just the most recent | LOW | Store or regenerate by tax year; value grows each year |
| Admin: per-loan interest breakdown in summary report | Accountant can verify each payment's interest component line by line | MEDIUM | Drill-down from summary to ledger detail |
| "1098 ready" status indicator in admin loan list | Admin can see at a glance which loans qualify this year before generating | LOW | Simple flag: interest_ytd >= 600 |
| Lender info pre-populated from admin settings | Admin doesn't re-enter Hot Springs Financial name/address/EIN each year | LOW | One-time setup in admin settings table |
| Email delivery confirmation log | Admin can see when each borrower's 1098 email was sent and opened | LOW | Resend already provides delivery events; just surface them |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| IRS e-filing (direct IRIS/FIRE submission) | "Automate everything" impulse | Complex IRS integration, TCC registration required, high maintenance for small portfolio; explicitly out of scope per PROJECT.md | Generate the accountant summary report + PDFs; accountant handles IRS submission manually or via tax software |
| Borrower TIN self-service edit | Seems like good UX | TINs are sensitive; self-edit without verification creates incorrect filing risk | Admin enters/verifies TIN; borrower sees masked last-4 only |
| Auto-send 1098 emails without admin review | Convenience | One bad TIN or wrong interest figure goes to borrowers and IRS before admin catches it | Admin triggers the batch send after reviewing the accountant summary report |
| Store 1098 PDFs permanently in Supabase Storage | Seems like good document management | Creates stale file problem (if payment is corrected after generation, stored PDF is wrong); adds storage cost | Generate on-demand from live data; optionally cache with a "regenerate" button |
| Note buyer 1098 generation | Completeness | Different tax treatment (note buyers receive principal + interest as investment income, not mortgage interest); needs separate research | Deferred to future milestone per PROJECT.md |
| 1099-INT generation | Sometimes confused with 1098 | 1099-INT is for savings interest, not mortgage interest; wrong form for this use case | 1098 is the correct form; do not conflate |

---

## Feature Dependencies

```
[Payment Ledger with interest/principal split]
    └──required by──> [Annual Interest Calculation]
                          └──required by──> [$600 Threshold Filter]
                          └──required by──> [1098 PDF Generation]
                                                └──required by──> [Borrower Portal Download]
                                                └──required by──> [January Email Delivery]
                          └──required by──> [Admin Accountant Summary Report]

[Borrower TIN (SSN) stored on borrower record]
    └──required by──> [1098 PDF Generation]
    └──required by──> [Admin Accountant Summary Report]

[Lender Info (name, address, EIN) in admin settings]
    └──required by──> [1098 PDF Generation]

[Loan origination date]
    └──required by──> [Mid-year pro-rata handling in Box 2]

[Loan status / payoff date]
    └──required by──> [Paid-off note inclusion logic]
```

### Dependency Notes

- **Annual interest calculation requires payment ledger with interest split:** Each payment record must already store the interest component separately from principal. The existing HSF payment ledger posts principal and interest separately — this dependency is already satisfied.
- **1098 PDF generation requires borrower TIN:** TIN is not currently stored on borrower records. This is the most likely missing data model field. Must be added before any PDF can be generated.
- **January email requires pg_cron + Resend:** Both are already in use for payment reminders. The same infrastructure handles 1098 delivery.
- **Admin summary report requires all of the above:** It is a rollup of data that PDF generation also needs. Build the calculation layer first, surface it in both the report and the PDF.

---

## MVP Definition

### Launch With (v1.1 — this milestone)

- [ ] Borrower TIN field added to data model and admin UI for entry
- [ ] Annual interest calculation per loan for a given tax year (from payment ledger)
- [ ] $600 threshold filter (exclude sub-threshold loans from generation)
- [ ] Paid-off note inclusion (filter by "active at any point in the tax year")
- [ ] Mid-year origination handling (Box 2 = principal at origination for first-year loans)
- [ ] 1098 PDF generation (Copy B layout, all required boxes populated)
- [ ] Borrower portal: view and download 1098 for the current tax year
- [ ] Admin accountant summary report (one row per qualifying loan: borrower name, TIN masked, interest total, principal balance, origination date, property address)
- [ ] Automated January email to qualifying borrowers (pg_cron trigger, Resend delivery)

### Add After Validation (v1.x)

- [ ] Tax year selector in borrower portal — add once first year is complete and value is proven
- [ ] Email delivery confirmation log — add when admin asks "did they get it?"
- [ ] "1098 ready" status badge in admin loan list — low-effort enhancement

### Future Consideration (v2+)

- [ ] Note buyer 1098 generation — requires separate research into 1099-INT/investment income treatment
- [ ] IRS e-filing via IRIS/FIRE — only if portfolio grows beyond ~50 loans (accountant manual filing scales fine until then)
- [ ] Prior-year amended 1098 generation — if a payment is corrected after filing

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Annual interest calculation | HIGH | LOW | P1 |
| $600 threshold filter | HIGH | LOW | P1 |
| Borrower TIN data model + admin entry | HIGH | LOW | P1 |
| 1098 PDF generation | HIGH | MEDIUM | P1 |
| Borrower portal download | HIGH | LOW | P1 |
| Admin accountant summary report | HIGH | MEDIUM | P1 |
| Paid-off note inclusion | HIGH | LOW | P1 |
| Mid-year pro-rata (Box 2) | HIGH | LOW | P1 |
| Automated January email | HIGH | MEDIUM | P1 |
| Tax year selector (borrower) | MEDIUM | LOW | P2 |
| Email delivery confirmation log | MEDIUM | LOW | P2 |
| "1098 ready" indicator (admin) | LOW | LOW | P2 |
| Lender info settings (pre-populate) | MEDIUM | LOW | P2 |
| IRS e-filing (IRIS/FIRE) | LOW | HIGH | P3 |
| Note buyer 1098 | MEDIUM | HIGH | P3 |

---

## Competitor Feature Analysis

| Feature | The Mortgage Office (TMO) | LoanPro | HSF Approach |
|---------|--------------------------|---------|--------------|
| 1098 generation | Batch generate, print/mail service available | API-driven, developer configures | On-demand PDF per borrower, admin-triggered batch email |
| Borrower portal access | Yes, borrower can download from portal | Yes, configurable | Yes, self-service download in existing borrower portal |
| Admin tax report | Summary report with IRS reconciliation view | Configurable reporting engine | Accountant summary table: one row per qualifying loan |
| TIN collection | Stored at loan origination | Stored in borrower profile | Admin enters via loan detail; borrower sees masked last-4 |
| E-filing | Supported via tax software export | Supported | Out of scope — accountant files manually |

---

## Sources

- [IRS Instructions for Form 1098 (Rev. December 2026)](https://www.irs.gov/instructions/i1098) — HIGH confidence, authoritative
- [IRS Form 1098 (Rev. April 2025) — actual form PDF](https://www.irs.gov/pub/irs-pdf/f1098.pdf) — HIGH confidence
- [IRS About Form 1098](https://www.irs.gov/forms-pubs/about-form-1098) — HIGH confidence
- [IRS Topic 801 — E-Filing Threshold](https://www.irs.gov/taxtopics/tc801) — HIGH confidence
- [Understanding Form 1098 Boxes — tax1099.com](https://www.tax1099.com/blog/form-1098-boxes/) — MEDIUM confidence, verified against IRS source
- [IRS Rules on Owner Financing — hallsirs.com](https://www.hallsirs.com/irs-rules-owner-financing/) — MEDIUM confidence
- [REtipster: What Is IRS Form 1098](https://retipster.com/irs-form-1098/) — MEDIUM confidence, land-specific perspective
- [LendFoundry Self-Service Borrower Portal](https://lendfoundry.com/solutions/loan-origination-software/self-service-borrower-portal/) — LOW confidence (marketing), used for UX baseline comparison only

---

*Feature research for: IRS Form 1098 Tax Reporting — HSF Owner-Finance Loan Servicing*
*Researched: 2026-04-08*
