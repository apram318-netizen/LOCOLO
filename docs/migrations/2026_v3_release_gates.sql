-- =============================================================================
-- 2026_v3_release_gates.sql — server-side gates for the App Store release.
--
--   1. Mint fee is enforced by the database, not the client.
--      - mint_orders lost its owner UPDATE policy: a user could set their own
--        order to 'paid' and mint free. Orders now change only through
--        SECURITY DEFINER code (create/attach RPCs, the verify-mint-purchase
--        edge function via service role).
--      - digital_assets INSERT by a signed-in user consumes one waived/paid,
--        unattached mint order of theirs, or fails. A fee of 0 in
--        app_config.mint_fee_usd turns the gate off (free minting).
--      - attach_mint_order becomes a no-op when the trigger already bound an
--        order to the asset, so the client's follow-up call can't consume a
--        second order.
--   2. iap_transactions: one row per verified App Store transaction (replay
--      guard), written only by the verify-mint-purchase edge function.
--   3. Marketplace kill switch: app_config.marketplace_enabled (false for
--      launch). Listings, bids and trades refuse signed-in writes while off;
--      the client hides the marketplace UI from the same flag.
--
-- Service-role / SQL-editor writes (auth.uid() IS NULL) bypass the gates.
-- Idempotent.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Mint orders
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS mo_update_self ON public.mint_orders;
REVOKE INSERT, UPDATE, DELETE ON public.mint_orders FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.enforce_mint_order()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  base_fee numeric := coalesce(
    (SELECT (value #>> '{}')::numeric FROM public.app_config WHERE key = 'mint_fee_usd'), 2.99);
  o uuid;
BEGIN
  IF auth.uid() IS NULL OR base_fee <= 0 THEN RETURN NEW; END IF;

  SELECT m.order_id INTO o
    FROM public.mint_orders m
   WHERE m.user_id = NEW.user_id AND m.asset_id IS NULL AND m.status IN ('waived', 'paid')
   ORDER BY m.created_at
   LIMIT 1
   FOR UPDATE SKIP LOCKED;
  IF o IS NULL THEN
    RAISE EXCEPTION 'mint fee not paid' USING ERRCODE = '42501',
      HINT = 'Complete the mint purchase before posting the asset.';
  END IF;

  UPDATE public.mint_orders SET asset_id = NEW.asset_id, status = 'consumed' WHERE order_id = o;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_mint_order() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS digital_assets_enforce_mint ON public.digital_assets;
CREATE TRIGGER digital_assets_enforce_mint
  AFTER INSERT ON public.digital_assets
  FOR EACH ROW EXECUTE FUNCTION public.enforce_mint_order();

CREATE OR REPLACE FUNCTION public.attach_mint_order(p_order uuid, p_asset uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me uuid := auth.uid(); o public.mint_orders%ROWTYPE;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  -- The insert trigger already bound an order to this asset.
  IF EXISTS (SELECT 1 FROM public.mint_orders WHERE asset_id = p_asset AND user_id = me) THEN
    RETURN;
  END IF;
  SELECT * INTO o FROM public.mint_orders WHERE order_id = p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mint order not found'; END IF;
  IF o.user_id <> me THEN RAISE EXCEPTION 'not your mint order' USING ERRCODE = '42501'; END IF;
  IF o.asset_id IS NOT NULL THEN
    IF o.asset_id = p_asset THEN RETURN; END IF;
    RAISE EXCEPTION 'mint order already used';
  END IF;
  IF o.status NOT IN ('waived', 'paid') THEN
    RAISE EXCEPTION 'mint order is not payable yet (status %)', o.status;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = p_asset AND d.user_id = me) THEN
    RAISE EXCEPTION 'asset not found or not yours';
  END IF;
  UPDATE public.mint_orders SET asset_id = p_asset, status = 'consumed' WHERE order_id = p_order;
END $$;
REVOKE ALL ON FUNCTION public.attach_mint_order(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_mint_order(uuid, uuid) TO authenticated;

CREATE INDEX IF NOT EXISTS mint_orders_open_idx ON public.mint_orders (user_id, created_at)
  WHERE asset_id IS NULL AND status IN ('waived', 'paid');

-- ---------------------------------------------------------------------------
-- 2. Verified App Store transactions (service role writes only)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.iap_transactions (
  transaction_id          text PRIMARY KEY,
  original_transaction_id text,
  user_id                 uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  order_id                uuid NOT NULL UNIQUE REFERENCES public.mint_orders(order_id) ON DELETE CASCADE,
  product_id              text NOT NULL,
  environment             text NOT NULL,
  purchased_at            timestamptz,
  created_at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS iap_transactions_user_idx ON public.iap_transactions (user_id);
ALTER TABLE public.iap_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iap_select_self ON public.iap_transactions;
CREATE POLICY iap_select_self ON public.iap_transactions FOR SELECT TO authenticated
  USING ((select auth.uid()) = user_id);
REVOKE ALL ON public.iap_transactions FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.iap_transactions FROM authenticated;
GRANT SELECT ON public.iap_transactions TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Marketplace kill switch
-- ---------------------------------------------------------------------------
INSERT INTO public.app_config (key, value) VALUES ('marketplace_enabled', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.enforce_marketplace_enabled()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT coalesce(
       (SELECT (value #>> '{}')::boolean FROM public.app_config WHERE key = 'marketplace_enabled'), false) THEN
    RAISE EXCEPTION 'the marketplace is not open yet' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_marketplace_enabled() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS asset_listings_marketplace_gate ON public.asset_listings;
CREATE TRIGGER asset_listings_marketplace_gate BEFORE INSERT ON public.asset_listings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_marketplace_enabled();
DROP TRIGGER IF EXISTS bids_marketplace_gate ON public.bids;
CREATE TRIGGER bids_marketplace_gate BEFORE INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.enforce_marketplace_enabled();
DROP TRIGGER IF EXISTS trades_marketplace_gate ON public.trades;
CREATE TRIGGER trades_marketplace_gate BEFORE INSERT ON public.trades
  FOR EACH ROW EXECUTE FUNCTION public.enforce_marketplace_enabled();

COMMIT;
