-- =============================================================================
-- LOCOLO V2 — Mint fee, coupons, provenance ledger, Ed25519 authenticity
--
-- CLAUDE: ACTION REQUIRED — this file is NOT applied to prod yet.
-- Owner will run it later in the Supabase SQL Editor. Until then, coupons
-- (LOCOLO100) and attach_mint_order will fail against live. Do not remove
-- this marker until LOCOLO_AR_STATUS.md §5.10 is checked off.
--
-- Idempotent. Safe to re-run on prod (where an earlier draft of this layer is
-- already live). Fixes preview_mint_fee's ambiguous `code` variable/column
-- clash that made every coupon (including LOCOLO100) fail.
--
-- Depends on: users, digital_assets, app_config (from notifications migration).
-- Companion client: MintingService, CryptoService (Ed25519), ARCreateViewModel.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- 1. Authenticity columns on digital_assets + users
-- ---------------------------------------------------------------------------
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS content_hash text,
  ADD COLUMN IF NOT EXISTS creator_signature text,
  ADD COLUMN IF NOT EXISTS creator_signing_key text,
  ADD COLUMN IF NOT EXISTS owner_id uuid REFERENCES public.users(user_id);

UPDATE public.digital_assets SET owner_id = user_id WHERE owner_id IS NULL;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS ed25519_public_key text,
  ADD COLUMN IF NOT EXISTS signing_key_updated_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2. coupons
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.coupons (
  code           text PRIMARY KEY,
  discount_type  text NOT NULL CHECK (discount_type IN ('percent', 'fixed')),
  discount_value numeric NOT NULL CHECK (discount_value >= 0),
  max_uses       int,
  used_count     int NOT NULL DEFAULT 0,
  expires_at     timestamptz,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coupons_select ON public.coupons;
-- Codes themselves aren't secret, but redemptions go through RPCs. Allow
-- authenticated reads so the admin UI / debugging can list them; the RPCs
-- are the only writers of used_count.
CREATE POLICY coupons_select ON public.coupons FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.coupons FROM anon, authenticated;
GRANT SELECT ON public.coupons TO authenticated;

INSERT INTO public.coupons (code, discount_type, discount_value, max_uses, active)
VALUES ('LOCOLO100', 'percent', 100, NULL, true)
ON CONFLICT (code) DO UPDATE
  SET discount_type = EXCLUDED.discount_type,
      discount_value = EXCLUDED.discount_value,
      active = true;

-- ---------------------------------------------------------------------------
-- 3. mint_orders
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mint_orders (
  order_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'waived', 'paid', 'consumed', 'expired', 'cancelled')),
  fee         numeric NOT NULL,
  discount    numeric NOT NULL DEFAULT 0,
  total       numeric NOT NULL,
  currency    text NOT NULL DEFAULT 'USD',
  coupon_code text REFERENCES public.coupons(code),
  asset_id    uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS mint_orders_user_idx ON public.mint_orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS mint_orders_open_idx ON public.mint_orders (user_id)
  WHERE status IN ('pending', 'waived', 'paid') AND asset_id IS NULL;

ALTER TABLE public.mint_orders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mo_select_self ON public.mint_orders;
DROP POLICY IF EXISTS mo_update_self ON public.mint_orders;
CREATE POLICY mo_select_self ON public.mint_orders FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
-- Clients may attach an asset_id to their own open order; status changes go
-- through SECURITY DEFINER RPCs.
CREATE POLICY mo_update_self ON public.mint_orders FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
REVOKE ALL ON public.mint_orders FROM anon, authenticated;
GRANT SELECT, UPDATE ON public.mint_orders TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. provenance_records (append-only authenticity ledger)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.provenance_records (
  record_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id    uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  event_type  text NOT NULL CHECK (event_type IN ('mint', 'transfer', 'list', 'sale', 'delist')),
  actor_id    uuid REFERENCES public.users(user_id) ON DELETE SET NULL,
  prev_hash   text,
  record_hash text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS provenance_asset_idx
  ON public.provenance_records (asset_id, created_at ASC);

ALTER TABLE public.provenance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pr_select ON public.provenance_records;
CREATE POLICY pr_select ON public.provenance_records FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.provenance_records FROM anon, authenticated;
GRANT SELECT ON public.provenance_records TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Mint fee config (app_config from notifications migration)
-- ---------------------------------------------------------------------------
INSERT INTO public.app_config (key, value)
VALUES ('mint_fee_usd', '2.99'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 6. preview_mint_fee — FIXED: never name a variable `code` (shadows coupons.code)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_mint_fee(p_coupon text DEFAULT NULL)
RETURNS TABLE(fee numeric, discount numeric, total numeric, valid boolean, reason text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  base_fee numeric := coalesce(
    (SELECT (value #>> '{}')::numeric FROM public.app_config WHERE key = 'mint_fee_usd'),
    2.99);
  coupon_row public.coupons%ROWTYPE;
  raw text := nullif(btrim(coalesce(p_coupon, '')), '');
  disc numeric := 0;
  ok boolean := true;
  why text := NULL;
BEGIN
  IF raw IS NOT NULL THEN
    SELECT * INTO coupon_row
      FROM public.coupons c
     WHERE upper(c.code) = upper(raw);

    IF NOT FOUND THEN
      ok := false; why := 'Unknown coupon code';
    ELSIF NOT coupon_row.active THEN
      ok := false; why := 'This coupon is no longer active';
    ELSIF coupon_row.expires_at IS NOT NULL AND coupon_row.expires_at < now() THEN
      ok := false; why := 'This coupon has expired';
    ELSIF coupon_row.max_uses IS NOT NULL AND coupon_row.used_count >= coupon_row.max_uses THEN
      ok := false; why := 'This coupon has been fully redeemed';
    ELSE
      IF coupon_row.discount_type = 'percent' THEN
        disc := round(base_fee * least(coupon_row.discount_value, 100) / 100.0, 2);
      ELSE
        disc := least(coupon_row.discount_value, base_fee);
      END IF;
    END IF;
  END IF;

  fee := base_fee;
  discount := disc;
  total := greatest(base_fee - disc, 0);
  valid := ok;
  reason := why;
  RETURN NEXT;
END $$;
REVOKE ALL ON FUNCTION public.preview_mint_fee(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_mint_fee(text) TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. create_mint_order — consumes a coupon when the order is waived/paid
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_mint_order(p_coupon text DEFAULT NULL)
RETURNS TABLE(order_id uuid, total numeric, status text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  me uuid := auth.uid();
  q record;
  new_id uuid;
  new_status text;
  raw text := nullif(btrim(coalesce(p_coupon, '')), '');
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO q FROM public.preview_mint_fee(raw);
  IF NOT q.valid THEN
    RAISE EXCEPTION '%', coalesce(q.reason, 'Invalid coupon') USING ERRCODE = '22023';
  END IF;

  new_status := CASE WHEN q.total <= 0 THEN 'waived' ELSE 'pending' END;

  -- Consume the coupon only when the order is created successfully.
  IF raw IS NOT NULL AND q.discount > 0 THEN
    UPDATE public.coupons c
       SET used_count = c.used_count + 1
     WHERE upper(c.code) = upper(raw)
       AND c.active
       AND (c.expires_at IS NULL OR c.expires_at >= now())
       AND (c.max_uses IS NULL OR c.used_count < c.max_uses);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon could not be redeemed' USING ERRCODE = '22023';
    END IF;
  END IF;

  INSERT INTO public.mint_orders
    (user_id, status, fee, discount, total, currency, coupon_code)
  VALUES
    (me, new_status, q.fee, q.discount, q.total, 'USD',
     CASE WHEN raw IS NULL THEN NULL ELSE upper(raw) END)
  RETURNING mint_orders.order_id INTO new_id;

  order_id := new_id;
  total := q.total;
  status := new_status;
  RETURN NEXT;
END $$;
REVOKE ALL ON FUNCTION public.create_mint_order(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_mint_order(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. attach_mint_order — bind a waived/paid order to the freshly inserted asset
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attach_mint_order(p_order uuid, p_asset uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  me uuid := auth.uid();
  o public.mint_orders%ROWTYPE;
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO o FROM public.mint_orders WHERE order_id = p_order FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mint order not found'; END IF;
  IF o.user_id <> me THEN RAISE EXCEPTION 'not your mint order' USING ERRCODE = '42501'; END IF;
  IF o.asset_id IS NOT NULL THEN
    IF o.asset_id = p_asset THEN RETURN; END IF; -- idempotent
    RAISE EXCEPTION 'mint order already used';
  END IF;
  IF o.status NOT IN ('waived', 'paid') THEN
    RAISE EXCEPTION 'mint order is not payable yet (status %)', o.status;
  END IF;
  IF NOT EXISTS (
       SELECT 1 FROM public.digital_assets d
        WHERE d.asset_id = p_asset AND d.user_id = me) THEN
    RAISE EXCEPTION 'asset not found or not yours';
  END IF;

  UPDATE public.mint_orders
     SET asset_id = p_asset, status = 'consumed'
   WHERE order_id = p_order;
END $$;
REVOKE ALL ON FUNCTION public.attach_mint_order(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.attach_mint_order(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. Genesis provenance row on asset insert (when content_hash is present)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.provenance_on_mint()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  payload text;
  hashed text;
BEGIN
  IF NEW.content_hash IS NULL OR length(NEW.content_hash) < 16 THEN
    RETURN NEW;
  END IF;
  -- Skip if a mint record already exists (re-runs / upserts).
  IF EXISTS (
       SELECT 1 FROM public.provenance_records
        WHERE asset_id = NEW.asset_id AND event_type = 'mint') THEN
    RETURN NEW;
  END IF;

  payload := concat_ws('|',
    'mint',
    lower(NEW.asset_id::text),
    lower(NEW.user_id::text),
    NEW.content_hash,
    coalesce(NEW.creator_signature, ''),
    coalesce(NEW.creator_signing_key, ''));
  hashed := encode(digest(convert_to(payload, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO public.provenance_records
    (asset_id, event_type, actor_id, prev_hash, record_hash)
  VALUES (NEW.asset_id, 'mint', NEW.user_id, NULL, hashed);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.provenance_on_mint() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS digital_assets_provenance_mint ON public.digital_assets;
CREATE TRIGGER digital_assets_provenance_mint
  AFTER INSERT ON public.digital_assets
  FOR EACH ROW EXECUTE FUNCTION public.provenance_on_mint();

-- Provenance on sale (buy_listing already flips owner_id)
CREATE OR REPLACE FUNCTION public.provenance_on_sale()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  prev text;
  payload text;
  hashed text;
BEGIN
  SELECT record_hash INTO prev
    FROM public.provenance_records
   WHERE asset_id = NEW.asset_id
   ORDER BY created_at DESC LIMIT 1;

  payload := concat_ws('|',
    'sale',
    lower(NEW.asset_id::text),
    lower(coalesce(NEW.seller_id::text, '')),
    lower(coalesce(NEW.buyer_id::text, '')),
    NEW.price::text,
    coalesce(prev, ''));
  hashed := encode(digest(convert_to(payload, 'UTF8'), 'sha256'), 'hex');

  INSERT INTO public.provenance_records
    (asset_id, event_type, actor_id, prev_hash, record_hash)
  VALUES (NEW.asset_id, 'sale', NEW.buyer_id, prev, hashed);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.provenance_on_sale() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trades_provenance_sale ON public.trades;
CREATE TRIGGER trades_provenance_sale
  AFTER INSERT ON public.trades
  FOR EACH ROW EXECUTE FUNCTION public.provenance_on_sale();

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.preview_mint_fee(NULL);            -- fee 2.99
--   select * from public.preview_mint_fee('LOCOLO100');     -- total 0, valid true
--   select * from public.preview_mint_fee('NOPE');          -- valid false
--   -- as signed-in user:
--   select * from public.create_mint_order('LOCOLO100');    -- status waived
--   select public.attach_mint_order('<order>','<asset>');
-- =============================================================================
