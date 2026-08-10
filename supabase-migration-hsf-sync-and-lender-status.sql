-- HSF sync hardening + lender portal status
--
-- Two problems this fixes, both found while tracing why an assigned note
-- (Lot 17 Claro Way) was invisible to its lender on Hickory Street Finance.
--
-- 1. `on_loan_assigned_sync_to_hsf` was AFTER UPDATE only. A loan saved with
--    the note buyer already filled in at creation never fired the sync, so it
--    only ever reached hsf_loans if someone happened to edit it again later.
--    Now fires on INSERT too.
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
  IF TG_OP = 'INSERT' THEN
    v_changed := true;
  ELSE
    v_changed := (OLD.nb_email IS DISTINCT FROM NEW.nb_email)
              OR (OLD.inv_date IS DISTINCT FROM NEW.inv_date);
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
