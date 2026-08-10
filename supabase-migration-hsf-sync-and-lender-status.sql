-- HSF sync hardening + lender portal status
--
-- Two problems this fixes, both found while tracing why an assigned note
-- (Lot 17 Claro Way) was invisible to its lender on Hickory Street Finance.
--
-- 1. `on_loan_assigned_sync_to_hsf` was AFTER UPDATE only, and even then only
--    reacted to nb_email / inv_date. A loan saved with the note buyer already
--    filled in at creation never synced at all, and a synced loan whose amount,
--    dates or address were later corrected in the CRM never re-synced -- the
--    portal kept serving the old values silently. Now fires on INSERT, and on
--    UPDATE of any field hsf_loans mirrors.
--
-- 2. The CRM had no way to tell whether a lender had actually been invited to
--    the portal, or had accepted. That lives in auth.users, which PostgREST
--    does not expose. `hsf_lender_portal_status()` returns it for admins only.
--
-- Both objects already existed in the database but not in the repo. Per
-- .planning/note-buyer-visibility.md, DB objects are the source of truth only
-- when mirrored here — this file is that mirror.

-- ---------------------------------------------------------------------------
-- 1. Sync trigger: fire on INSERT as well as UPDATE
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trigger_crm_sync_to_hsf()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  sync_url    text;
  sync_secret text;
  v_changed   boolean;
BEGIN
  -- Never sync a wrap note to the note-buyer-facing hsf_loans (isolation).
  IF COALESCE(NEW.note_type, 'underlying') = 'wrap' THEN
    RETURN NEW;
  END IF;

  -- OLD is not assigned during INSERT; referencing it there raises. Treat an
  -- insert as "changed" so a loan created with the buyer already filled in
  -- syncs immediately instead of waiting for an unrelated later edit.
  --
  -- On UPDATE, compare every field hsf_loans mirrors -- not just nb_email and
  -- inv_date as before. hsf_loans is a copy, so any mirrored field edited in
  -- the CRM and not re-pushed leaves the portal showing stale data with nothing
  -- to indicate it. That had already happened to 8 notes: five lenders were
  -- being shown the wrong first payment date, two of them out by four months.
  --
  -- Fields not mirrored into hsf_loans (loan_servicer, notes, sold, status,
  -- paperstac_posted, ...) are deliberately excluded, so ordinary CRM edits
  -- don't generate pointless HTTP posts.
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

  IF (NEW.nb_email IS NOT NULL AND NEW.nb_email <> '')
     AND (NEW.inv_date IS NOT NULL)
     AND v_changed
  THEN
    SELECT value INTO sync_url    FROM app_settings WHERE key = 'hsf_sync_url';
    SELECT value INTO sync_secret FROM app_settings WHERE key = 'hsf_sync_secret';

    IF sync_url IS NOT NULL AND sync_secret IS NOT NULL THEN
      PERFORM net.http_post(
        url     := sync_url,
        body    := jsonb_build_object('crm_loan_id', NEW.id::text),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || sync_secret
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_loan_assigned_sync_to_hsf ON public.loans;

CREATE TRIGGER on_loan_assigned_sync_to_hsf
  AFTER INSERT OR UPDATE ON public.loans
  FOR EACH ROW EXECUTE FUNCTION public.trigger_crm_sync_to_hsf();

-- ---------------------------------------------------------------------------
-- 2. Lender portal status, for the CRM's invite indicator
-- ---------------------------------------------------------------------------
-- Returns one row per note_buyer account. The CRM joins this to note_lenders
-- by email to show not-invited / invited-pending / signed-in. Admin-gated
-- inside the function body: a non-admin caller gets zero rows, never an error,
-- so the indicator degrades to "unknown" rather than breaking the lender list.

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
-- 3. Unassigning a note in the CRM clears the lender on HSF
-- ---------------------------------------------------------------------------
-- The sync only ever added or updated. Taking a lender off a note in LandFlow
-- -- routine when a buyer cancels -- left the portal holding the old
-- assignment: lender name, email and purchase price, on a note the CRM shows
-- as unassigned. Three notes were in that state since 12 June (Lot 2 and Lot 3
-- Asturias Dr, Lot 3 Pamplona Cir), each still filed to a lender who had no
-- portal account. Nothing was visible: the CRM had no lender to show, the
-- lender list counted zero notes for him, and the one view that would have
-- displayed them needed an account he did not have.
--
-- This writes hsf_loans directly rather than going through /api/crm-sync,
-- because that endpoint rejects a note with no lender -- the very state we are
-- trying to record.
--
-- The row itself is kept, not deleted: every note belongs on the portal
-- whether or not it has a lender. inv_date is left alone because hsf_loans
-- declares it NOT NULL -- the schema assumes every note has an assignment,
-- which is the same assumption behind the API validation and the reason
-- lender-less notes cannot sync at all yet.

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
