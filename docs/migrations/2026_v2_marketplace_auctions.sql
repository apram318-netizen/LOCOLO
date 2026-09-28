-- =============================================================================
-- LOCOLO V2 — Auction place-bid + settle RPCs (Phase A completion)
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.21).
-- Apply after Phase A (`2026_v2_marketplace_phase_a.sql`). Idempotent.
-- Bids table already exists; this adds atomic place_bid + settle_auction.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.place_bid(p_listing uuid, p_amount numeric)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  l public.asset_listings%ROWTYPE;
  bid_id uuid;
  prev_top numeric;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO l FROM public.asset_listings WHERE listing_id = p_listing FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'listing not found'; END IF;
  IF l.status <> 'active' THEN RAISE EXCEPTION 'listing not active'; END IF;
  IF l.kind <> 'auction' THEN RAISE EXCEPTION 'not an auction'; END IF;
  IF l.ends_at IS NOT NULL AND l.ends_at < now() THEN RAISE EXCEPTION 'auction ended'; END IF;
  IF l.seller_id = uid THEN RAISE EXCEPTION 'cannot bid on own listing'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'invalid bid'; END IF;

  SELECT coalesce(max(amount), l.price) INTO prev_top
    FROM public.bids WHERE listing_id = p_listing AND status = 'active';
  IF p_amount <= prev_top THEN
    RAISE EXCEPTION 'bid must beat current high (% )', prev_top;
  END IF;

  UPDATE public.bids SET status = 'outbid'
   WHERE listing_id = p_listing AND status = 'active' AND bidder_id <> uid;

  INSERT INTO public.bids (listing_id, asset_id, bidder_id, amount, currency, status)
  VALUES (p_listing, l.asset_id, uid, p_amount, l.currency, 'active')
  RETURNING bids.bid_id INTO bid_id;

  UPDATE public.asset_listings SET price = p_amount WHERE listing_id = p_listing;
  UPDATE public.digital_assets SET current_value = p_amount WHERE asset_id = l.asset_id;

  RETURN bid_id;
END $$;
REVOKE ALL ON FUNCTION public.place_bid(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_bid(uuid, numeric) TO authenticated;

CREATE OR REPLACE FUNCTION public.settle_auction(p_listing uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  l public.asset_listings%ROWTYPE;
  top public.bids%ROWTYPE;
  trade_id uuid;
  royalty numeric := 0;
  fee numeric := 0;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  SELECT * INTO l FROM public.asset_listings WHERE listing_id = p_listing FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'listing not found'; END IF;
  IF l.kind <> 'auction' THEN RAISE EXCEPTION 'not an auction'; END IF;
  IF l.status <> 'active' THEN RAISE EXCEPTION 'listing not active'; END IF;
  IF l.seller_id <> uid THEN RAISE EXCEPTION 'only seller can settle' USING ERRCODE = '42501'; END IF;
  IF l.ends_at IS NOT NULL AND l.ends_at > now() THEN
    RAISE EXCEPTION 'auction still open';
  END IF;

  SELECT * INTO top FROM public.bids
   WHERE listing_id = p_listing AND status = 'active'
   ORDER BY amount DESC, created_at ASC LIMIT 1;
  IF NOT FOUND THEN
    UPDATE public.asset_listings SET status = 'expired' WHERE listing_id = p_listing;
    UPDATE public.digital_assets SET is_for_sale = false WHERE asset_id = l.asset_id;
    RETURN NULL;
  END IF;

  fee := round(top.amount * 0.05, 2);
  INSERT INTO public.trades (asset_id, seller_id, buyer_id, price, currency, royalty_paid, platform_fee)
  VALUES (l.asset_id, l.seller_id, top.bidder_id, top.amount, l.currency, royalty, fee)
  RETURNING trades.trade_id INTO trade_id;

  UPDATE public.bids SET status = 'accepted' WHERE bid_id = top.bid_id;
  UPDATE public.bids SET status = 'outbid'
   WHERE listing_id = p_listing AND status = 'active' AND bid_id <> top.bid_id;
  UPDATE public.asset_listings SET status = 'sold' WHERE listing_id = p_listing;
  UPDATE public.digital_assets
     SET owner_id = top.bidder_id, is_for_sale = false, current_value = top.amount
   WHERE asset_id = l.asset_id;

  RETURN trade_id;
END $$;
REVOKE ALL ON FUNCTION public.settle_auction(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.settle_auction(uuid) TO authenticated;

COMMIT;
