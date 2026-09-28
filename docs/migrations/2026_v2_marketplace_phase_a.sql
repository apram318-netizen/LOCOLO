-- =============================================================================
-- LOCOLO V2 — Marketplace Phase A (off-chain). Applied to prod 2026-09-28.
--
-- Off-chain trading foundation: ownership, listings, bids, immutable trades,
-- portfolio snapshots, and an atomic buy RPC. NO real money/crypto yet — that's
-- Phase B (fiat) and Phase C (on-chain). Reuses price_history + DigitalAsset
-- marketplace columns. Applied in 3 idempotent steps.
--
-- ⚠️ NAMING: there is a LEGACY `public.listings` table from the old app with a
-- different schema (no asset_id). The AR marketplace uses `asset_listings`.
-- =============================================================================

-- --- Step 1: ownership + price provenance --------------------------------
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES public.users(user_id);
UPDATE public.digital_assets SET owner_id = user_id WHERE owner_id IS NULL;
ALTER TABLE public.price_history
  ADD COLUMN IF NOT EXISTS source text;   -- 'sale' | 'listing' | 'mint' | 'oracle'

-- --- Step 2: wallets, asset_listings, bids, trades, portfolio_snapshots ---
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  address text NOT NULL, chain text NOT NULL DEFAULT 'base', provider text,
  is_primary boolean NOT NULL DEFAULT true, linked_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, address, chain)
);
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
CREATE POLICY wallets_all_self ON public.wallets FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.wallets TO authenticated;

CREATE TABLE IF NOT EXISTS public.asset_listings (
  listing_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  seller_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  kind text NOT NULL DEFAULT 'fixed' CHECK (kind IN ('fixed','auction')),
  price numeric NOT NULL CHECK (price >= 0), currency text NOT NULL DEFAULT 'USDC',
  ends_at timestamptz,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','sold','cancelled','expired')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS asset_listings_active_idx ON public.asset_listings (asset_id) WHERE status = 'active';
ALTER TABLE public.asset_listings ENABLE ROW LEVEL SECURITY;
CREATE POLICY al_select ON public.asset_listings FOR SELECT TO authenticated USING (true);
CREATE POLICY al_insert_seller ON public.asset_listings FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_listings.asset_id AND d.owner_id = auth.uid()));
CREATE POLICY al_update_seller ON public.asset_listings FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id) WITH CHECK (auth.uid() = seller_id);
GRANT SELECT, INSERT, UPDATE ON public.asset_listings TO authenticated;

CREATE TABLE IF NOT EXISTS public.bids (
  bid_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid REFERENCES public.asset_listings(listing_id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  bidder_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK (amount > 0), currency text NOT NULL DEFAULT 'USDC',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','accepted','outbid','withdrawn','expired')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS bids_asset_idx ON public.bids (asset_id, created_at DESC);
ALTER TABLE public.bids ENABLE ROW LEVEL SECURITY;
CREATE POLICY bids_select ON public.bids FOR SELECT TO authenticated USING (true);
CREATE POLICY bids_insert_self ON public.bids FOR INSERT TO authenticated WITH CHECK (auth.uid() = bidder_id);
CREATE POLICY bids_update_self ON public.bids FOR UPDATE TO authenticated
  USING (auth.uid() = bidder_id) WITH CHECK (auth.uid() = bidder_id);
GRANT SELECT, INSERT, UPDATE ON public.bids TO authenticated;

CREATE TABLE IF NOT EXISTS public.trades (
  trade_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  seller_id uuid REFERENCES public.users(user_id), buyer_id uuid REFERENCES public.users(user_id),
  price numeric NOT NULL, currency text NOT NULL DEFAULT 'USDC',
  royalty_paid numeric NOT NULL DEFAULT 0, platform_fee numeric NOT NULL DEFAULT 0,
  tx_hash text, settled_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS trades_asset_idx ON public.trades (asset_id, settled_at DESC);
CREATE INDEX IF NOT EXISTS trades_buyer_idx ON public.trades (buyer_id, settled_at DESC);
ALTER TABLE public.trades ENABLE ROW LEVEL SECURITY;
CREATE POLICY trades_select ON public.trades FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.trades TO authenticated;   -- writes only via buy_listing RPC

CREATE TABLE IF NOT EXISTS public.portfolio_snapshots (
  user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  day date NOT NULL, total_value numeric NOT NULL, holdings_count int NOT NULL,
  currency text NOT NULL DEFAULT 'USDC', PRIMARY KEY (user_id, day)
);
ALTER TABLE public.portfolio_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY ps_all_self ON public.portfolio_snapshots FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portfolio_snapshots TO authenticated;

-- --- Step 3: buy_listing RPC (atomic off-chain settle) -------------------
CREATE OR REPLACE FUNCTION public.buy_listing(p_listing uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me uuid := auth.uid(); l public.asset_listings%ROWTYPE;
        royalty numeric; fee numeric; new_trade uuid;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO l FROM public.asset_listings WHERE listing_id = p_listing FOR UPDATE;
  IF NOT FOUND OR l.status <> 'active' THEN RAISE EXCEPTION 'listing not available'; END IF;
  IF l.kind <> 'fixed' THEN RAISE EXCEPTION 'auctions settle differently'; END IF;
  IF l.seller_id = me THEN RAISE EXCEPTION 'cannot buy your own listing'; END IF;
  royalty := round(l.price * 0.075, 2); fee := round(l.price * 0.025, 2);
  UPDATE public.digital_assets SET owner_id = me WHERE asset_id = l.asset_id;
  INSERT INTO public.trades (asset_id, seller_id, buyer_id, price, currency, royalty_paid, platform_fee)
  VALUES (l.asset_id, l.seller_id, me, l.price, l.currency, royalty, fee) RETURNING trade_id INTO new_trade;
  INSERT INTO public.price_history (asset_id, price, source) VALUES (l.asset_id, l.price, 'sale');
  UPDATE public.asset_listings SET status = 'sold' WHERE listing_id = p_listing;
  RETURN new_trade;
END $$;
REVOKE ALL ON FUNCTION public.buy_listing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.buy_listing(uuid) TO authenticated;
