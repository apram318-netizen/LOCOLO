-- =============================================================================
-- LOCOLO V2 Phase B — Fiat payment intents + creator payouts
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.18).
-- No card data ever stored. Partner refs only (Stripe / Coinbase Onramp).
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.payment_intents (
  intent_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  provider     text NOT NULL CHECK (provider IN ('stripe','coinbase_onramp','moonpay','apple_pay')),
  provider_ref text NOT NULL,
  amount       numeric NOT NULL CHECK (amount > 0),
  currency     text NOT NULL DEFAULT 'USD',
  purpose      text NOT NULL CHECK (purpose IN ('buy_asset','onramp_usdc','mint_fee')),
  asset_id     uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  mint_order_id uuid,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','succeeded','failed','refunded','cancelled')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payment_intents_user_idx
  ON public.payment_intents (user_id, created_at DESC);

ALTER TABLE public.payment_intents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pi_select_self ON public.payment_intents;
CREATE POLICY pi_select_self ON public.payment_intents FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
-- Inserts/updates only via SECURITY DEFINER edge fn / create_payment_intent RPC.
GRANT SELECT ON public.payment_intents TO authenticated;

CREATE TABLE IF NOT EXISTS public.payouts (
  payout_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  provider     text NOT NULL,
  provider_ref text,
  amount       numeric NOT NULL CHECK (amount > 0),
  currency     text NOT NULL DEFAULT 'USD',
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','processing','paid','failed','cancelled')),
  created_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payouts_select_self ON public.payouts;
CREATE POLICY payouts_select_self ON public.payouts FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
GRANT SELECT ON public.payouts TO authenticated;

-- Client creates a pending intent; edge fn / partner webhook marks succeeded.
CREATE OR REPLACE FUNCTION public.create_payment_intent(
  p_provider text,
  p_amount numeric,
  p_currency text,
  p_purpose text,
  p_asset uuid DEFAULT NULL,
  p_mint_order uuid DEFAULT NULL
)
RETURNS public.payment_intents
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  row public.payment_intents;
  pref text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid amount' USING ERRCODE = '22023';
  END IF;
  pref := 'pending_' || replace(gen_random_uuid()::text, '-', '');
  INSERT INTO public.payment_intents (
    user_id, provider, provider_ref, amount, currency, purpose, asset_id, mint_order_id
  ) VALUES (
    uid, p_provider, pref, p_amount, coalesce(nullif(p_currency,''),'USD'),
    p_purpose, p_asset, p_mint_order
  ) RETURNING * INTO row;
  RETURN row;
END $$;
REVOKE ALL ON FUNCTION public.create_payment_intent(text, numeric, text, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_payment_intent(text, numeric, text, text, uuid, uuid) TO authenticated;

COMMIT;
