-- Hold harmless: store the typed signature, not just the timestamp
--
-- The lender must accept a hold harmless agreement before they get access to
-- anything in the HSF portal, signing it by typing their name. note_lenders
-- already tracked *whether* and *which version* they accepted, but had nowhere
-- to put the name they typed -- so an acceptance carried no signature.
--
-- Both columns are nullable and additive: the nine existing acceptances stay
-- valid, with a null signature, and nothing that reads this table breaks.
--
-- Not put in `servicing_agreements`, despite that table having exactly the
-- right shape (signed_name, signed_at, ip_address, user_agent) and being empty:
-- its loan_id and parcel_id are NOT NULL, making it strictly per-note. The hold
-- harmless is one-time per lender, before they can reach any note at all.
--
-- The gate itself is portal work -- see .planning/hold-harmless-gate.md.

ALTER TABLE public.note_lenders
  ADD COLUMN IF NOT EXISTS hold_harmless_signed_name text,
  ADD COLUMN IF NOT EXISTS hold_harmless_ip          text;

COMMENT ON COLUMN public.note_lenders.hold_harmless_signed_name IS
  'Name the lender typed to sign the hold harmless agreement. Null for acceptances recorded before this field existed.';

COMMENT ON COLUMN public.note_lenders.hold_harmless_ip IS
  'Request IP at the moment of acceptance. Evidence of execution.';
