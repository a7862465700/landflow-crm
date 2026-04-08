# Pitfalls Research

**Domain:** IRS Form 1098 Tax Reporting — Owner-Finance Land Loan Platform
**Researched:** 2026-04-08
**Confidence:** HIGH (IRS official instructions verified, multiple authoritative sources)

---

## Critical Pitfalls

### Pitfall 1: Reporting Interest Accrued vs. Interest Received

**What goes wrong:**
The system calculates "interest earned" based on the amortization schedule and reports that figure on the 1098, rather than reporting interest actually received in cash during the calendar year. A borrower who underpays or skips payments will have a different accrued interest figure than cash received.

**Why it happens:**
Amortization schedules produce a clean "interest earned" number per period. Developers naturally pull this figure. But Form 1098 Box 1 requires **received** interest — the sum of cash payments received during the calendar year, interest-component only.

**How to avoid:**
Sum the `interest_amount` column from the payment ledger for payments with a `received_date` (not scheduled date) falling in the tax year. Do not use the amortization schedule's expected interest column. Build a dedicated tax-year interest query that joins payments to their received-date.

**Warning signs:**
- Interest figure on 1098 matches amortization schedule exactly but borrower had missed payments
- System using `due_date` instead of `received_date` to bucket payments into tax years
- Late or partial payments not reflected in 1098 discrepancy

**Phase to address:** Phase 1 — Interest Calculation Engine (data query layer)

---

### Pitfall 2: Tax Year Boundary Cut — December/January Timing

**What goes wrong:**
A borrower mails a January payment that arrives December 30, or a December payment that clears January 2. The system assigns it to the wrong tax year, causing the 1098 to either over-report or under-report interest by one full payment's worth of interest.

**Why it happens:**
The IRS rule is nuanced: interest is reportable in the year it was **received** AND **accrues** by December 31. Payments received in December but covering interest that doesn't fully accrue until after January 15 of the next year must be split. Most payment systems just use a single date field and assign the full payment to one year.

**IRS Rule (from official instructions):**
- Interest received in the current year that fully accrues by January 15 of the following year → reportable in the current year
- If any part of an interest payment accrues after January 15 → only the portion accruing by December 31 is reportable in the current year

**How to avoid:**
Use the payment's `received_date` as the controlling date for most cases. For payments received in December that cover a period extending past January 15, prorate. In practice for a simple monthly installment loan with a fixed payment date, the edge cases are rare — document your assumption and apply it consistently. Recommend: use `received_date`, treat any payment received by December 31 as in-year, and note this as a known simplification in admin documentation.

**Warning signs:**
- System using `due_date` or `scheduled_date` to assign payments to years
- December payments not appearing in the correct year's total
- No clear test case for a payment received December 28 vs. January 3

**Phase to address:** Phase 1 — Interest Calculation Engine

---

### Pitfall 3: The $600 Threshold Applies Per Mortgage, Not Per Borrower

**What goes wrong:**
A borrower has two active loans. Each loan received $450 in interest during the year. The system sees $900 total from that borrower and generates a 1098. But the IRS threshold is **per mortgage** — neither loan meets the $600 threshold individually, so no 1098 is required for either.

**Why it happens:**
Developers query total interest by borrower_id, not by loan_id. The threshold check runs at the wrong level of aggregation.

**How to avoid:**
Always calculate and threshold-check at the individual loan (note) level. A borrower with multiple loans may receive multiple 1098s (one per qualifying loan) or no 1098 at all if no single loan crossed $600. The query: `WHERE tax_year_interest >= 600 GROUP BY loan_id`.

**Warning signs:**
- Threshold check queries `SUM(interest) GROUP BY borrower_id`
- Single 1098 issued for borrower with two active loans that individually are under $600
- Edge case loans (small balance, high-interest, short-year) near the $600 line not tested

**Phase to address:** Phase 1 — Interest Calculation Engine

---

### Pitfall 4: Paid-Off Loans Excluded from 1098 Generation

**What goes wrong:**
The 1098 generation query filters for "active loans only." A loan that paid off in July still received, say, $800 in interest January–July. No 1098 is generated.

**Why it happens:**
Loan status filters in queries naturally exclude `status = 'paid_off'`. It's obvious when you think about it, but the query won't fail — it just silently omits the qualifying record.

**How to avoid:**
The 1098 eligibility query must be based on **interest received during the tax year**, not current loan status. Filter: loans that had any payments received in the tax year with interest >= $600, regardless of current status. Explicitly test the paid-off scenario with a fixture.

**Warning signs:**
- Query includes `WHERE status = 'active'` or equivalent
- No test cases with loans that closed mid-year
- Admin accountant report doesn't list any paid-off borrowers even when loans were active earlier in the year

**Phase to address:** Phase 1 — Interest Calculation Engine

---

### Pitfall 5: Mid-Year Loan Start — Wrong Box 2 (Outstanding Principal)

**What goes wrong:**
Box 2 on Form 1098 requires "outstanding principal as of January 1 of the reporting year." For a loan originated on March 15 of the tax year, the correct Box 2 value is the **original loan amount as of origination date** — not $0 (it didn't exist yet), and not the balance on December 31.

**Why it happens:**
The IRS rule for Box 2: if the loan was originated in the current year, enter the principal as of origination date. If the loan existed on January 1, enter the January 1 balance. Developers who don't read the Box 2 instructions closely compute it as a balance snapshot on January 1, which is $0 for new loans — technically wrong.

**How to avoid:**
Box 2 logic: `IF loan.origination_date in tax_year THEN loan.original_principal ELSE balance_as_of_jan1`. For a paid-off loan (paid off before January 1 of the filing year), Box 2 is $0 — but in that case, there should be no 1098 for that year at all (covered by Pitfall 4).

**Warning signs:**
- Box 2 is always pulled as a point-in-time balance snapshot with no conditional for origination year
- Mid-year loans show $0 in Box 2 in test PDFs
- No test fixture for a loan originated mid-year

**Phase to address:** Phase 2 — PDF Generation

---

### Pitfall 6: PDF Layout Does Not Match Official IRS Form

**What goes wrong:**
A custom-rendered PDF "looks like" a 1098 but doesn't match the official IRS layout. The copy furnished to the borrower (Copy B) must substantially match the official form. If a borrower's tax software can't interpret it, or an IRS auditor compares it to what was filed and the amounts don't reconcile, it creates compliance exposure.

**Why it happens:**
Developers generate a custom PDF with labels and boxes positioned by hand. This is time-consuming to get right and easy to get wrong — especially field positioning, the "CORRECTED" checkbox, required boilerplate language, and the three-copy structure (Copy A for IRS, Copy B for borrower, Copy C for lender records).

**How to avoid:**
Use the official IRS Copy B fillable PDF (`https://www.irs.gov/pub/irs-pdf/f1098.pdf`) as the source document. Overlay data using a PDF library (pdf-lib, PDFKit with coordinate mapping) rather than building from scratch. Test the output against the official form visually with actual data. Do not rely on a hand-drawn HTML/CSS layout.

**Warning signs:**
- PDF generated with HTML-to-PDF (Puppeteer, wkhtmltopdf) using a custom template
- Box numbers don't match IRS numbering
- "CORRECTED" checkbox not present
- Missing required boilerplate: "This is important tax information and is being furnished to the IRS."

**Phase to address:** Phase 2 — PDF Generation

---

### Pitfall 7: Vacant Land — Box 7/8 Property Address for Parcels Without Street Addresses

**What goes wrong:**
Owner-financed land parcels — especially rural, vacant lots — frequently do not have assigned street addresses. Box 8 requires a property address. If left blank or filled with a borrower mailing address when the property address differs, the form is technically incorrect.

**Why it happens:**
Web forms expect an address. Developers map `property.address` to Box 8 without considering that the parcel may only have a legal description or APN.

**How to avoid:**
Per IRS instructions: if the property has no street address, enter the **Assessor Parcel Number (APN)** and jurisdiction in Box 8. The CRM already stores parcel data — ensure the APN field is populated and used as a fallback when no street address exists. Box 7 (checkbox: same as borrower address) should be left unchecked for land parcels with different or missing addresses.

**Warning signs:**
- Box 8 defaulting to borrower's mailing address for vacant land parcels
- No APN-fallback logic in the Box 8 field
- Test PDFs showing the borrower's residential address instead of the collateral parcel address

**Phase to address:** Phase 2 — PDF Generation

---

### Pitfall 8: Emailing 1098 PDFs as Attachments Exposes PII

**What goes wrong:**
The system generates 1098 PDFs and attaches them directly to emails. The PDF contains the borrower's full SSN (or partial SSN), loan balance, and interest amount. Unencrypted email attachments persist indefinitely on mail servers, backup systems, and recipient inboxes.

**Why it happens:**
Attaching a PDF to an email notification is the obvious, easiest implementation. The risk is invisible until a breach occurs.

**How to avoid:**
Do not attach the 1098 PDF to emails. Send a notification email with a secure link to the borrower portal where they authenticate and download the PDF. The PDF stays in Supabase Storage (or served via a signed URL with expiration). This matches the existing HSF borrower portal pattern — borrowers already log in to view documents.

**Warning signs:**
- Email notification code attaches a generated PDF buffer directly to the SendGrid/Resend call
- No authentication step between email receipt and PDF access
- PDF accessible via a public/non-expiring URL in the email body

**Phase to address:** Phase 3 — Borrower Portal + Email Notification

---

### Pitfall 9: TIN/SSN Missing or Mismatched — Triggers IRS B Notice

**What goes wrong:**
A 1098 is filed with the IRS with a missing or incorrect borrower TIN (SSN). The IRS issues a CP2100 "B Notice" requiring the lender to begin 24% backup withholding on future payments and send a formal solicitation letter to the borrower. This is a cascading compliance problem that starts from a single incorrect field.

**Why it happens:**
Borrower onboarding in the CRM may not have collected SSNs — land sale closings often don't require SSN collection the way mortgage originations do. If the SSN field is empty or was entered incorrectly, the 1098 gets filed with a blank or wrong TIN.

**How to avoid:**
- Require SSN collection at borrower record creation (or at the latest, during the annual 1098 generation workflow)
- Validate SSN format (9 digits, not all zeros, not a placeholder) before generating 1098s
- Surface a "Borrower SSN missing" warning in the admin accountant report
- Implement an annual TIN solicitation reminder if SSN is blank

**Warning signs:**
- Borrower records with no SSN field or a null SSN in the database
- 1098 generation workflow proceeds without validating SSN presence
- Admin report doesn't flag missing TINs as a pre-flight check

**Phase to address:** Phase 1 — Interest Calculation Engine / Admin Report

---

### Pitfall 10: IRS e-File Threshold — 10+ Returns Requires FIRE/IRIS System

**What goes wrong:**
The platform files 1098s on paper (or the admin prints and mails Copy A to the IRS). If the total number of information returns filed in a year (all types combined: 1098s, 1099s, etc.) reaches 10 or more, e-filing is **legally required**. The threshold counts all information return types together, not per form type.

**IRS update:** The FIRE system (current e-file portal) is being retired after Tax Year 2026 / Filing Season 2027. The replacement is IRIS (Information Returns Intake System). Any e-file integration must target IRIS going forward.

**Why it happens:**
Small lenders assume the paper-filing path is always acceptable. The out-of-scope decision (manual IRS filing by accountant) is correct for the current MVP, but the platform must surface the threshold warning so the accountant knows when they cross into mandatory e-file territory.

**How to avoid:**
- Admin accountant report should include a total count of 1098s generated and a notice: "If your total information returns this year (1098s + 1099s) reach 10 or more, IRS e-filing is required."
- Note in documentation that IRS e-filing (FIRE/IRIS) is out of scope; this is an accountant responsibility
- Do not build FIRE integration for v1.1 — correctly deferred

**Warning signs:**
- Accountant report has no count of total forms generated
- No guidance to accountant about the 10-return e-file threshold
- Platform marketed as "IRS filing compliant" without distinguishing form generation from IRS submission

**Phase to address:** Phase 3 — Admin Accountant Report

---

### Pitfall 11: Late Fee and Other Charges Included in Box 1 Interest

**What goes wrong:**
The payment ledger stores each payment with columns for interest, principal, and fees (late fees, etc.). If the query sums the wrong column — or if historical payments were entered as a single lump "amount" without splitting interest vs. fees — Box 1 will be overstated, and the borrower's tax deduction will be inflated.

**Why it happens:**
Data entry shortcuts: some payments logged as a total amount with no breakdown. Or fees tagged as "interest" in the database for accounting convenience. The 1098 query trusts the `interest_amount` column without validating it.

**How to avoid:**
- Audit the payment ledger schema: ensure interest, principal, and late fee amounts are stored in separate columns (not one `amount` field)
- If any legacy payments exist as lump sums, surface them in the admin report as "payments requiring manual review"
- Never include late fees or servicing fees in Box 1 — only interest on the principal obligation

**Warning signs:**
- Payment table has a single `amount` column with no interest/principal split
- Late fee entries categorized as payment type "interest"
- Box 1 totals match total payments received rather than just interest

**Phase to address:** Phase 1 — Interest Calculation Engine

---

### Pitfall 12: Corrected 1098 Workflow Not Built

**What goes wrong:**
A 1098 is generated and emailed to a borrower in January. In February, an error is found (wrong interest total due to a payment data correction). There is no mechanism to generate a "CORRECTED" 1098, notify the borrower, and file a correction with the IRS.

**Why it happens:**
The correction workflow is invisible during initial build. Developers build "generate and send" but not "generate corrected version and re-send with CORRECTED checkbox marked."

**How to avoid:**
- The PDF generation function must accept a `corrected: boolean` flag that stamps the "CORRECTED" checkbox on the form
- Admin UI must allow regenerating a 1098 for a specific borrower/year with the correction flag
- Correction sends a new email notification to the borrower
- A corrected 1098 also requires re-filing with the IRS (accountant's responsibility, but the admin report must indicate which forms were corrected)

**Warning signs:**
- No `corrected` field in the 1098 records table
- Admin UI has no "Re-generate corrected 1098" action
- PDF template has no "CORRECTED" checkbox

**Phase to address:** Phase 2 — PDF Generation

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use amortization schedule interest instead of ledger interest | Simpler query | Wrong Box 1 when payments are late or missed | Never |
| Skip TIN validation, file with blank SSN | Faster onboarding | IRS B notice, backup withholding obligation | Never |
| Email PDF as attachment | Simpler notification code | PII exposure in unencrypted email | Never |
| Use `due_date` instead of `received_date` for tax year bucketing | No code change needed | Wrong year assignment for late/early payments | Never |
| Build custom PDF layout instead of filling official IRS form | Full design control | Layout errors, form noncompliance, accessibility failures | Never for IRS forms |
| Skip corrected-1098 workflow for v1.1 | Faster initial build | No recovery path when errors found after sending | Acceptable if documented as known gap |
| Single 1098 per borrower (not per loan) | Simpler data model | Incorrect threshold check, wrong form count | Never |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| IRS official PDF form | Recreating the layout from scratch in HTML/CSS | Fill the official Copy B PDF using pdf-lib coordinate overlay |
| Supabase Storage for 1098 PDFs | Storing generated PDFs in the same `vault_files` base64 table | Store in Supabase Storage bucket with signed URLs — PDFs can be large and should be streamable |
| Resend/SendGrid email notification | Attaching PDF buffer to email | Send notification-only email with authenticated portal link |
| Payment ledger (existing) | Summing `amount` column for interest | Query `interest_amount` column specifically; validate column exists and is populated |
| IRS IRIS e-file system | Building FIRE integration (being retired) | Document that e-filing is accountant's responsibility; if ever built, target IRIS not FIRE |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Generating all 1098 PDFs in a single synchronous request | Admin page times out during January generation run | Generate PDFs lazily (on-demand per borrower) or via background job | 20+ borrowers |
| Storing generated PDFs as base64 in the database | DB size bloat, slow queries on vault table | Use Supabase Storage bucket for generated PDFs, store only a reference URL | Any scale |
| Recalculating interest totals on every 1098 view | Slow portal load for borrowers | Cache or store tax-year interest total in a `tax_year_summaries` table after generation | 50+ payments per loan |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| 1098 PDFs accessible without authentication (public URLs) | Any person with the URL can see SSN, loan balance, interest | Use Supabase Storage signed URLs with short expiration (1 hour), require portal login first |
| SSN stored in plain text in borrower record | Data breach exposes full SSNs | Encrypt SSN at rest or store only last 4 digits for display; use full SSN only during 1098 generation |
| Admin accountant report accessible without admin role check | Note buyer or borrower could access all borrowers' tax data | Enforce admin-only RLS on tax reporting endpoints |
| Logging full 1098 data (including SSN) in application logs | Log aggregation services capture PII | Mask SSN in all logging; log only loan_id and tax_year |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Borrower receives no notification that 1098 is available | Borrower calls asking where their form is; may miss tax deadline | Send email notification in early January with portal link |
| 1098 only available in portal with no download option | Borrower can't save or print for their accountant | Always provide a "Download PDF" button, not just an in-browser viewer |
| Admin report is a raw data dump with no pre-flight warnings | Accountant receives report with missing SSNs and must discover errors themselves | Pre-flight section at top of report: "X borrowers missing SSN," "Y loans near $600 threshold" |
| No indication that a corrected 1098 supersedes the original | Borrower files taxes with old (incorrect) form | Corrected 1098 email should clearly state "This CORRECTED form supersedes the one sent on [date]" |
| January email sent before 1098s are verified by admin | Borrower receives incorrect form before accountant review | Admin must explicitly approve/trigger the send; do not auto-send on January 1 |

---

## "Looks Done But Isn't" Checklist

- [ ] **Interest calculation:** Verify that the query uses `received_date` not `due_date` and sums `interest_amount` not `total_amount`
- [ ] **$600 threshold:** Verify threshold is checked per loan (loan_id), not per borrower
- [ ] **Paid-off loans:** Verify that loans with `status = 'paid_off'` that had activity in the tax year ARE included
- [ ] **Box 2 — mid-year origination:** Verify that loans originated during the tax year show origination principal, not $0
- [ ] **Box 8 — vacant land:** Verify that APN is used when no street address exists for the collateral parcel
- [ ] **CORRECTED checkbox:** Verify the PDF template has the CORRECTED checkbox and the generation function can activate it
- [ ] **TIN validation:** Verify admin report flags borrowers with missing or malformed SSNs before send
- [ ] **Email security:** Verify the notification email contains a portal link, not a PDF attachment
- [ ] **Signed URLs:** Verify PDF download links expire and require authentication
- [ ] **Late fees excluded:** Verify Box 1 sums only interest, not late fees or other charges
- [ ] **Multi-loan borrowers:** Test a borrower with two loans where one qualifies and one doesn't

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong interest amount filed with IRS | HIGH | Generate corrected 1098 with CORRECTED checkbox; re-furnish to borrower by January 31; file correction with IRS before March 31 (e-file) or March 2 (paper) |
| TIN mismatch triggers IRS B Notice | HIGH | Send first B Notice to borrower within 15 days of receiving CP2100; begin backup withholding if no response within 30 days; file corrected 1098 once correct TIN obtained |
| PDF sent as email attachment (PII exposed) | MEDIUM | Notify affected borrowers; revoke access to exposed document if possible; update process to portal-link-only going forward |
| Wrong tax year for a payment (boundary error) | MEDIUM | Identify affected loans; generate corrected 1098s; accountant files corrections with IRS |
| Paid-off loan 1098 not generated | MEDIUM | Identify omitted loans; generate and furnish late 1098s; IRS penalty clock starts from January 31 deadline |
| Box 2 wrong (mid-year origination) | LOW | Issue corrected 1098; low direct tax impact for borrower but technically incorrect |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Interest received vs. earned | Phase 1 — Interest Calculation | Test: compare query output to manually summed payment ledger for a borrower with missed payments |
| Tax year boundary (Dec/Jan timing) | Phase 1 — Interest Calculation | Test: payment received Dec 30 appears in year N; payment received Jan 2 appears in year N+1 |
| Per-mortgage $600 threshold | Phase 1 — Interest Calculation | Test: borrower with two loans at $450 each generates no 1098s |
| Paid-off loans excluded | Phase 1 — Interest Calculation | Test: loan paid off in July with $800 interest generates a 1098 |
| Box 2 mid-year origination | Phase 2 — PDF Generation | Test: PDF for loan originated May 15 shows origination principal in Box 2, not $0 |
| PDF layout accuracy | Phase 2 — PDF Generation | Visual comparison against official IRS f1098.pdf; all box numbers and positions verified |
| Vacant land Box 8 (APN fallback) | Phase 2 — PDF Generation | Test: parcel with no street address shows APN + jurisdiction in Box 8 |
| Email PII security | Phase 3 — Email Notification | Verify notification email HTML contains no PDF attachment; link requires auth |
| Missing TIN / SSN validation | Phase 1 — Admin Report Pre-flight | Test: borrower with null SSN surfaces in admin pre-flight warnings |
| e-File threshold warning | Phase 3 — Admin Accountant Report | Verify report includes total 1098 count and e-file threshold notice |
| Late fees in Box 1 | Phase 1 — Interest Calculation | Test: payment with late fee does not inflate interest total |
| Corrected 1098 workflow | Phase 2 — PDF Generation | Test: admin can regenerate with CORRECTED flag; PDF has CORRECTED checkbox marked |

---

## Sources

- [IRS Instructions for Form 1098 (Rev. December 2026)](https://www.irs.gov/instructions/i1098) — Official, HIGH confidence
- [IRS Form 1098 PDF (April 2025)](https://www.irs.gov/pub/irs-pdf/f1098.pdf) — Official form layout, HIGH confidence
- [IRS About Form 1098](https://www.irs.gov/forms-pubs/about-form-1098) — Filing thresholds, deadlines, HIGH confidence
- [IRS FIRE System — e-File Information Returns](https://www.irs.gov/e-file-providers/filing-information-returns-electronically-fire) — e-file requirements, FIRE retirement timeline, HIGH confidence
- [IRS IRIS System](https://www.irs.gov/filing/e-file-information-returns-with-iris) — FIRE replacement, HIGH confidence
- [IRS Backup Withholding B Program](https://www.irs.gov/businesses/small-businesses-self-employed/backup-withholding-b-program) — TIN mismatch consequences, HIGH confidence
- [Note Servicing Center — Accurate IRS Form 1098 Guide for Private Mortgage Lenders](https://noteservicingcenter.com/accurate-irs-form-1098-a-guide-for-private-mortgage-lenders/) — Private lender-specific guidance, MEDIUM confidence
- [tax1099.com — IRS Form 1098 Filing Requirements](https://www.tax1099.com/blog/1098-filing-requirements/) — $600 per-mortgage threshold, MEDIUM confidence
- [Moneylender Forums — Form 1098 Principal in Box 2 is wrong](https://moneylenderprofessional.com/forum/viewtopic.php?t=93) — Real-world Box 2 errors, MEDIUM confidence
- [IRS General Instructions for Certain Information Returns (2025)](https://www.irs.gov/instructions/i1099gi) — Aggregate 10-return e-file threshold, HIGH confidence
- [Kiteworks — Sending PII Over Email](https://www.kiteworks.com/secure-email/send-pii-over-email/) — Email PII security, MEDIUM confidence

---
*Pitfalls research for: IRS Form 1098 Tax Reporting — Owner-Finance Land Loan Platform (HSF v1.1)*
*Researched: 2026-04-08*
