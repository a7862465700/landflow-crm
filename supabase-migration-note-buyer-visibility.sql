-- ============================================================
-- LandFlow CRM — Fix: note buyers cannot see their notes in the
-- Hickory Street Finance (HSF) note-buyer portal.
--
-- Symptom: an investor (e.g. "KANDU CAPITAL" / kanduinvesting@gmail.com)
-- signs in to the portal but sees none of the notes assigned to them,
-- even though the notes exist and carry the correct nb_email.
--
-- Three independent defects were found and are fixed here:
--
--   1. hsf_loans (the note-buyer-facing notes table) had RLS enabled but
--      only ADMIN read/update policies — there was no policy allowing a
--      note buyer to read their own rows. So every note buyer's portal
--      query returned zero rows. (This is the reported symptom.)
--      note_lenders already had the equivalent email-scoped read policy;
--      hsf_loans was simply missing it.
--
--   2. loans.buyer_user_id could point at the WRONG buyer. The
--      autolink_loan_to_buyer() trigger only stamped buyer_user_id when it
--      was NULL and never re-resolved it. When a note was reassigned to a
--      different buyer (nb_email changed on an already-linked loan), the
--      stale buyer_user_id from the previous buyer was left in place. The
--      new buyer then saw nothing via the "Buyers see own purchased loans"
--      RLS on loans/payments/late_fees, and — worse — the previous buyer
--      kept read access to the reassigned note and its payments
--      (a cross-account data leak).
--
--   3. Existing rows already carried the stale linkage and are corrected
--      by the backfill below.
--
-- Safe to run more than once (idempotent).
-- ============================================================

-- ------------------------------------------------------------
-- Fix 1: let note buyers read their own rows in hsf_loans.
-- Mirrors the existing "Note buyer reads own note_lenders" policy:
-- match on the email in the caller's JWT (case-insensitive).
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "Note buyer reads own hsf_loans" ON public.hsf_loans;
CREATE POLICY "Note buyer reads own hsf_loans"
  ON public.hsf_loans
  FOR SELECT
  USING (lower(nb_email) = lower((auth.jwt() ->> 'email')));

-- ------------------------------------------------------------
-- Fix 2: autolink_loan_to_buyer() must re-resolve buyer_user_id when the
-- note buyer changes, and clear it when the note is unassigned — instead
-- of sticking permanently to the first value it ever set.
--
-- Resolution is now authoritative: the note_buyer auth account whose email
-- matches the loan's current nb_email. (The prior "copy buyer_user_id from
-- another loan with the same email" step was what propagated stale/wrong
-- ids and has been removed.)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.autolink_loan_to_buyer()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user          uuid;
  v_email_changed boolean;
BEGIN
  -- Treat INSERT as an email change; on UPDATE detect whether the
  -- note-buyer email actually changed (case/whitespace-insensitive).
  v_email_changed := (TG_OP = 'INSERT')
    OR (lower(trim(coalesce(NEW.nb_email, '')))
        IS DISTINCT FROM lower(trim(coalesce(OLD.nb_email, ''))));

  -- No note buyer assigned → the note is unowned; drop any stale linkage
  -- so a previously-assigned buyer loses portal access.
  IF NEW.nb_email IS NULL OR trim(NEW.nb_email) = '' THEN
    NEW.buyer_user_id := NULL;
    RETURN NEW;
  END IF;

  -- Email unchanged and already linked → leave as-is so ordinary edits
  -- (status, payments, etc.) don't churn the link.
  IF NOT v_email_changed AND NEW.buyer_user_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Authoritative resolution: the note_buyer auth account whose email
  -- matches the current note-buyer email.
  SELECT u.id
    INTO v_user
    FROM auth.users u
    JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'note_buyer'
   WHERE lower(trim(u.email)) = lower(trim(NEW.nb_email))
   LIMIT 1;

  -- Stamp the resolved buyer (NULL if they haven't signed up yet), which
  -- also clears a link that belonged to a previously-assigned buyer.
  NEW.buyer_user_id := v_user;
  RETURN NEW;
END;
$function$;

-- ------------------------------------------------------------
-- Fix 3: backfill existing rows so buyer_user_id matches the account that
-- owns the loan's current nb_email. Only rows whose stored value differs
-- from the authoritative value are touched (KANDU's notes today); rows
-- that are already correct or have no buyer account yet are left alone.
-- ------------------------------------------------------------
UPDATE loans l
   SET buyer_user_id = sub.uid
  FROM (
    SELECT l2.id,
           ( SELECT u.id
               FROM auth.users u
               JOIN user_roles ur ON ur.user_id = u.id AND ur.role = 'note_buyer'
              WHERE lower(trim(u.email)) = lower(trim(l2.nb_email))
              LIMIT 1 ) AS uid
      FROM loans l2
     WHERE l2.nb_email IS NOT NULL AND trim(l2.nb_email) <> ''
  ) sub
 WHERE l.id = sub.id
   AND l.buyer_user_id IS DISTINCT FROM sub.uid;
