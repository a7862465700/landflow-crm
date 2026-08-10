-- HSF sync: every note on the portal, kept current, without the API
--
-- Traced from "an assigned note is invisible on Hickory Street" (Lot 17 Claro
-- Way) down to the sync itself. Four changes.
--
-- The shape of the problem: hsf_loans is a *copy* of loans, written by POSTing
-- to the portal's /api/crm-sync. Payments never had any of these faults
-- because payments were never copied -- one shared table, both apps reading it.
--
-- Per .planning/note-buyer-visibility.md the repo is the record for DB objects,
-- and it had drifted; this file is the mirror.

-- ---------------------------------------------------------------------------
-- 1. Sync writes hsf_loans directly instead of calling /api/crm-sync
-- ---------------------------------------------------------------------------
-- Three faults, one cause:
--
--   * AFTER UPDATE only -- a loan created with the buyer already filled in
--     never synced at all.
--   * Reacted only to nb_email / inv_date -- a note whose amount, dates or
--     address were later corrected never re-synced, and the portal served the
--     old values silently. Eight notes had drifted; five lenders were being
--     shown the wrong first payment date, two of them out by four months.
--   * /api/crm-sync rejects a note with no nb_email + inv_date (422
--     VALIDATION_FAILED, confirmed by testing one). Notes serviced in-house
--     have neither, so 37 of 92 could not reach the portal at all.
--
-- The endpoint turned out to be a straight field copy -- verified across all
-- 52 lender rows, every mirrored column matched its source in loans and
-- note_lenders exactly, with no transformation. So the database can do the
-- write itself, which sidesteps the validation entirely and closes the drift
-- window to zero.
--
-- Deliberately NOT written here: lender_address, lender_phone,
-- lender_bank_name, lender_ach_routing_number, lender_account_number. The
-- lender enters those themselves in the portal; they flow portal -> note_lenders
-- and are none of the CRM's business. Overwriting them from here would destroy
-- data the CRM never had.

CREATE OR REPLACE FUNCTION public.trigger_crm_sync_to_hsf()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_changed  boolean;
  v_name     text;
  v_business text;
BEGIN
  -- Wrap notes are never exposed to note buyers (buyer isolation).
  IF COALESCE(NEW.note_type, 'underlying') = 'wrap' THEN RETURN NEW; END IF;

  -- OLD is unassigned during INSERT; referencing it there raises.
  IF TG_OP = 'INSERT' THEN
    v_changed := true;
  ELSE
    v_changed := (
      OLD.borrower, OLD.email, OLD.phone, OLD.loan_amount, OLD.rate, OLD.term,
      OLD.orig_date, OLD.first_pay_date, OLD.nb_name, OLD.nb_email, OLD.nb_business,
      OLD.inv_date, OLD.inv_price, OLD.parcel, OLD.address
    ) IS DISTINCT FROM (
      NEW.borrower, NEW.email, NEW.phone, NEW.loan_amount, NEW.rate, NEW.term,
      NEW.orig_date, NEW.first_pay_date, NEW.nb_name, NEW.nb_email, NEW.nb_business,
      NEW.inv_date, NEW.inv_price, NEW.parcel, NEW.address
    );
  END IF;

  -- Fields hsf_loans does not mirror (loan_servicer, notes, sold, status,
  -- paperstac_posted, ...) fall out here, so routine CRM edits are free.
  IF NOT v_changed THEN RETURN NEW; END IF;

  -- note_lenders is the canonical lender identity; loans.nb_name is whatever
  -- was typed on that particular note and carries per-loan variants.
  SELECT nl.name, nl.business INTO v_name, v_business
    FROM note_lenders nl
   WHERE coalesce(trim(NEW.nb_email), '') <> ''
     AND lower(trim(nl.email)) = lower(trim(NEW.nb_email))
   LIMIT 1;

  INSERT INTO hsf_loans (
    crm_loan_id, borrower, email, phone, loan_amount, rate, term,
    orig_date, first_pay_date, nb_name, nb_email, nb_business,
    inv_date, inv_price, parcel, address, last_synced_at
  ) VALUES (
    NEW.id, coalesce(NEW.borrower,''), coalesce(NEW.email,''), NEW.phone,
    coalesce(NEW.loan_amount,0), NEW.rate, NEW.term, NEW.orig_date, NEW.first_pay_date,
    coalesce(v_name, nullif(trim(coalesce(NEW.nb_name,'')),''), ''),
    coalesce(trim(NEW.nb_email),''),
    coalesce(v_business, nullif(trim(coalesce(NEW.nb_business,'')),''), ''),
    NEW.inv_date, coalesce(NEW.inv_price,0), NEW.parcel, NEW.address, now()
  )
  ON CONFLICT (crm_loan_id) DO UPDATE SET
    borrower       = EXCLUDED.borrower,
    email          = EXCLUDED.email,
    phone          = EXCLUDED.phone,
    loan_amount    = EXCLUDED.loan_amount,
    rate           = EXCLUDED.rate,
    term           = EXCLUDED.term,
    orig_date      = EXCLUDED.orig_date,
    first_pay_date = EXCLUDED.first_pay_date,
    nb_name        = EXCLUDED.nb_name,
    nb_email       = EXCLUDED.nb_email,
    nb_business    = EXCLUDED.nb_business,
    inv_date       = EXCLUDED.inv_date,
    inv_price      = EXCLUDED.inv_price,
    parcel         = EXCLUDED.parcel,
    address        = EXCLUDED.address,
    last_synced_at = now();

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_loan_assigned_sync_to_hsf ON public.loans;

CREATE TRIGGER on_loan_assigned_sync_to_hsf
  AFTER INSERT OR UPDATE ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.trigger_crm_sync_to_hsf();

-- ---------------------------------------------------------------------------
-- 2. Assignment date is not mandatory
-- ---------------------------------------------------------------------------
-- hsf_loans.inv_date was NOT NULL, so the table could not represent a note
-- with no assignment -- every note serviced in-house. The schema half of the
-- same assumption behind the API validation. Existing dates are left alone.
--
-- nb_email stays NOT NULL: '' satisfies it, and that is what an unassigned
-- note writes. A date has no equivalent empty value, so this was the only
-- column that actually blocked anything.

ALTER TABLE public.hsf_loans ALTER COLUMN inv_date DROP NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Unassigning a note in the CRM clears the lender on HSF
-- ---------------------------------------------------------------------------
-- The sync only ever added or updated. Taking a lender off a note in LandFlow
-- -- routine when a buyer cancels -- left the portal holding the old
-- assignment. Three notes sat like that from 12 June (Lot 2 and Lot 3 Asturias
-- Dr, Lot 3 Pamplona Cir), each filed to a lender with no portal account.
--
-- Invisible from every screen: the CRM had no lender to show, the lender list
-- counted zero notes for him, and the view that would have shown them needed
-- an account he did not have. Nothing was exposed for that same reason -- but
-- an invite would have handed him three notes he does not own, with prices.
--
-- Clears the lender's banking details from the *note* (a copy of a lender who
-- no longer holds it), not from note_lenders, which is the lender's own record.
-- The row is kept, not deleted: every note belongs on the portal, assigned or
-- not.

CREATE OR REPLACE FUNCTION public.clear_hsf_lender_on_unassign()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF coalesce(trim(OLD.nb_email), '') <> '' AND coalesce(trim(NEW.nb_email), '') = '' THEN
    UPDATE hsf_loans
       SET nb_email = '', nb_name = '', nb_business = '', inv_price = 0,
           lender_notes = null, lender_address = null, lender_phone = null,
           lender_bank_name = null, lender_ach_routing_number = null,
           lender_account_number = null,
           last_synced_at = now()
     WHERE crm_loan_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_loan_unassigned_clear_hsf ON public.loans;

CREATE TRIGGER on_loan_unassigned_clear_hsf
  AFTER UPDATE OF nb_email ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.clear_hsf_lender_on_unassign();

-- ---------------------------------------------------------------------------
-- 4. Lender portal status, for the CRM's invite indicator
-- ---------------------------------------------------------------------------
-- Returns one row per note_buyer account. The CRM joins this to note_lenders
-- by email to show not-invited / invited-pending / signed-in. Lives in
-- auth.users, which PostgREST does not expose. Admin-gated inside the body: a
-- non-admin caller gets zero rows, never an error, so the indicator degrades
-- to "unknown" rather than breaking the lender list.

CREATE OR REPLACE FUNCTION public.hsf_lender_portal_status()
RETURNS TABLE (
  email           text,
  invited_at      timestamptz,
  confirmed_at    timestamptz,
  last_sign_in_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF (SELECT ur.role FROM user_roles ur WHERE ur.user_id = auth.uid()) IS DISTINCT FROM 'admin'::app_role THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT lower(trim(u.email))::text,
           u.invited_at,
           u.email_confirmed_at,
           u.last_sign_in_at
      FROM auth.users u
      JOIN user_roles r ON r.user_id = u.id AND r.role = 'note_buyer';
END;
$$;

REVOKE ALL ON FUNCTION public.hsf_lender_portal_status() FROM public;
GRANT EXECUTE ON FUNCTION public.hsf_lender_portal_status() TO authenticated;

-- ---------------------------------------------------------------------------
-- Backfill (one-time; the trigger handles everything from here)
-- ---------------------------------------------------------------------------
-- Mirrors the trigger's mapping exactly. Safe to re-run.

INSERT INTO hsf_loans (
  crm_loan_id, borrower, email, phone, loan_amount, rate, term,
  orig_date, first_pay_date, nb_name, nb_email, nb_business,
  inv_date, inv_price, parcel, address, last_synced_at
)
SELECT l.id, coalesce(l.borrower,''), coalesce(l.email,''), l.phone,
       coalesce(l.loan_amount,0), l.rate, l.term, l.orig_date, l.first_pay_date,
       coalesce(nl.name, nullif(trim(coalesce(l.nb_name,'')),''), ''),
       coalesce(trim(l.nb_email),''),
       coalesce(nl.business, nullif(trim(coalesce(l.nb_business,'')),''), ''),
       l.inv_date, coalesce(l.inv_price,0), l.parcel, l.address, now()
FROM loans l
LEFT JOIN note_lenders nl
  ON coalesce(trim(l.nb_email),'') <> '' AND lower(trim(nl.email)) = lower(trim(l.nb_email))
WHERE coalesce(l.note_type,'underlying') <> 'wrap'
  AND l.id NOT IN (SELECT crm_loan_id FROM hsf_loans WHERE crm_loan_id IS NOT NULL)
ON CONFLICT (crm_loan_id) DO NOTHING;
