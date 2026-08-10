-- Hold harmless: version control and an append-only acceptance history
--
-- Goal: re-prompt lenders who already signed, so they accept updated terms at
-- their next sign-in. Two things were missing.
--
-- 1. Nowhere to say what the current version *is*. The nine existing
--    acceptances all carry '2026-06-02', but no setting records which version
--    is live, so the portal must be hardcoding it -- meaning re-prompting
--    everyone needs a code deploy. Now an app_settings row.
--
-- 2. Re-signing would have destroyed the record of the previous signature.
--    note_lenders holds one acceptance per lender; accepting again overwrites
--    it. For an agreement whose whole purpose is to be enforceable later, the
--    June signatures cannot be collateral damage of asking for August ones.
--    Now an append-only history table, backfilled with all nine.
--
-- Deliberately NOT done: nulling hold_harmless_accepted_at to force the
-- prompt. That erases the record of what they signed and when. The version
-- comparison does the same job without destroying evidence -- see the gate
-- logic in .planning/hold-harmless-gate.md.
--
-- Also deliberately NOT done: setting a new version string. The value below is
-- the one already live. Inventing '2026-08-10' would assert an agreement
-- revision that may not exist yet. Bump it when the new text is written; that
-- single change re-prompts everyone.

-- ---------------------------------------------------------------------------
-- 1. Append-only acceptance history
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.hold_harmless_acceptances (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lender_email  text NOT NULL,
  lender_name   text,
  version       text,
  accepted_at   timestamptz NOT NULL,
  signed_name   text,
  ip            text,
  recorded_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS hold_harmless_acceptances_email_idx
  ON public.hold_harmless_acceptances (lower(lender_email), accepted_at DESC);

ALTER TABLE public.hold_harmless_acceptances ENABLE ROW LEVEL SECURITY;

-- Admin read only. No INSERT policy: rows arrive via the SECURITY DEFINER
-- trigger below, never from a client, so the history cannot be forged or
-- edited through the API.
DROP POLICY IF EXISTS "Admin reads hold_harmless_acceptances" ON public.hold_harmless_acceptances;
CREATE POLICY "Admin reads hold_harmless_acceptances" ON public.hold_harmless_acceptances
  FOR SELECT USING ((SELECT ur.role FROM user_roles ur WHERE ur.user_id = auth.uid()) = 'admin'::app_role);

-- ---------------------------------------------------------------------------
-- 2. Capture every acceptance as it happens
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.log_hold_harmless_acceptance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.hold_harmless_accepted_at IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.hold_harmless_accepted_at IS DISTINCT FROM OLD.hold_harmless_accepted_at)
  THEN
    INSERT INTO hold_harmless_acceptances
      (lender_email, lender_name, version, accepted_at, signed_name, ip)
    VALUES
      (lower(trim(NEW.email)), NEW.name, NEW.hold_harmless_version,
       NEW.hold_harmless_accepted_at, NEW.hold_harmless_signed_name, NEW.hold_harmless_ip);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS note_lenders_log_hold_harmless ON public.note_lenders;

CREATE TRIGGER note_lenders_log_hold_harmless
  AFTER INSERT OR UPDATE OF hold_harmless_accepted_at ON public.note_lenders
  FOR EACH ROW EXECUTE FUNCTION public.log_hold_harmless_acceptance();

-- ---------------------------------------------------------------------------
-- 3. Backfill the nine existing acceptances
-- ---------------------------------------------------------------------------
-- Idempotent on (email, accepted_at), so re-running this file is safe.

INSERT INTO public.hold_harmless_acceptances
  (lender_email, lender_name, version, accepted_at, signed_name, ip)
SELECT lower(trim(nl.email)), nl.name, nl.hold_harmless_version,
       nl.hold_harmless_accepted_at, nl.hold_harmless_signed_name, nl.hold_harmless_ip
FROM note_lenders nl
WHERE nl.hold_harmless_accepted_at IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM hold_harmless_acceptances a
    WHERE lower(a.lender_email) = lower(trim(nl.email))
      AND a.accepted_at = nl.hold_harmless_accepted_at
  );

-- ---------------------------------------------------------------------------
-- 4. Current agreement version
-- ---------------------------------------------------------------------------
-- Set to what is already live. Bump this one row when the terms change and
-- every lender is re-prompted at their next sign-in -- no deploy.

INSERT INTO public.app_settings (key, value)
VALUES ('hold_harmless_version', '2026-06-02')
ON CONFLICT (key) DO NOTHING;
