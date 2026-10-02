-- =============================================================================
-- 2026_v3_offers_fix.sql — fix "new row for relation offers violates check
-- constraint offers_status_check" when accepting / rejecting an offer.
--
-- Cause: the legacy prod CHECK allowed (pending, accepted, declined,
-- cancelled). The app (OfferListView / OfferViewModel), the notify_on_offer
-- trigger and the offers_update_* RLS policies all use 'rejected' /
-- 'withdrawn', which the old constraint refuses.
--
-- This migration:
--   1. normalises any legacy spellings already stored,
--   2. replaces the CHECK with the full lifecycle the app uses,
--   3. adds respond_to_offer() so accepting is atomic: the chosen offer is
--      accepted, every other pending offer on the asset is rejected, and the
--      asset's highest_offer / active_offers counters are recomputed.
--
-- Idempotent. Run in the Supabase SQL editor (search_path includes
-- extensions for PostGIS — see LOCOLO_AR_STATUS §6b).
-- =============================================================================

BEGIN;

-- 1. Normalise legacy values so the new CHECK can be validated.
UPDATE public.offers SET status = 'accepted'  WHERE lower(status) IN ('accept', 'approved', 'approve');
UPDATE public.offers SET status = 'rejected'  WHERE lower(status) IN ('reject', 'declined', 'decline', 'denied');
UPDATE public.offers SET status = 'withdrawn' WHERE lower(status) IN ('cancelled', 'canceled', 'withdraw');
UPDATE public.offers SET status = 'pending'   WHERE status IS NULL OR lower(status) IN ('open', 'active', 'new');

-- 2. Replace the constraint.
ALTER TABLE public.offers DROP CONSTRAINT IF EXISTS offers_status_check;
ALTER TABLE public.offers
  ADD CONSTRAINT offers_status_check
  CHECK (status IN ('pending', 'accepted', 'rejected', 'withdrawn', 'expired'));
ALTER TABLE public.offers ALTER COLUMN status SET DEFAULT 'pending';
ALTER TABLE public.offers ALTER COLUMN status SET NOT NULL;
-- respond_to_offer, notify_on_offer and update_asset_offer_stats all filter
-- by asset (+ status); the FK had no covering index (advisor 0001).
CREATE INDEX IF NOT EXISTS offers_asset_status_idx ON public.offers (asset_id, status);

-- 3. Atomic accept / reject by the asset's current owner.
CREATE OR REPLACE FUNCTION public.respond_to_offer(p_offer uuid, p_accept boolean)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  o      public.offers%ROWTYPE;
  owner  uuid;
  result text := CASE WHEN p_accept THEN 'accepted' ELSE 'rejected' END;
BEGIN
  SELECT * INTO o FROM public.offers WHERE offer_id = p_offer FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'offer not found' USING ERRCODE = 'P0002'; END IF;

  SELECT coalesce(da.owner_id, da.user_id) INTO owner
    FROM public.digital_assets da WHERE da.asset_id = o.asset_id;
  IF owner IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'only the owner can respond to offers' USING ERRCODE = '42501';
  END IF;
  IF o.status <> 'pending' THEN
    RAISE EXCEPTION 'offer is already %', o.status USING ERRCODE = '22023';
  END IF;

  UPDATE public.offers SET status = result WHERE offer_id = p_offer;

  IF p_accept THEN
    -- One winner: close the rest (the notify trigger tells each buyer).
    UPDATE public.offers SET status = 'rejected'
     WHERE asset_id = o.asset_id AND offer_id <> p_offer AND status = 'pending';
  END IF;

  UPDATE public.digital_assets da SET
    active_offers = (SELECT count(*) FROM public.offers
                      WHERE asset_id = o.asset_id AND status = 'pending'),
    highest_offer = (SELECT max(amount) FROM public.offers
                      WHERE asset_id = o.asset_id AND status IN ('pending', 'accepted'))
   WHERE da.asset_id = o.asset_id;

  RETURN result;
END $$;

REVOKE ALL ON FUNCTION public.respond_to_offer(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_offer(uuid, boolean) TO authenticated;

COMMIT;
