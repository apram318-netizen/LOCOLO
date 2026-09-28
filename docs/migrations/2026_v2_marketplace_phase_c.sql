-- =============================================================================
-- LOCOLO V2 Phase C — On-chain foundation (nft_tokens + Seaport columns)
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.19).
-- Wallets table already exists from Phase A. This adds token metadata +
-- seaport_order on listings. No mainnet contracts — schema only until audit.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.nft_tokens (
  asset_id     uuid PRIMARY KEY REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  chain        text NOT NULL DEFAULT 'base',
  contract     text,
  token_id     numeric,
  metadata_uri text,
  edition_size int NOT NULL DEFAULT 1 CHECK (edition_size >= 1),
  royalty_bps  int NOT NULL DEFAULT 750 CHECK (royalty_bps BETWEEN 0 AND 10000),
  mint_state   text NOT NULL DEFAULT 'unminted'
                 CHECK (mint_state IN ('unminted','pending','minted','failed')),
  owner_id     uuid REFERENCES public.users(user_id),
  minted_at    timestamptz
);

ALTER TABLE public.nft_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS nft_select ON public.nft_tokens;
DROP POLICY IF EXISTS nft_insert_owner ON public.nft_tokens;
CREATE POLICY nft_select ON public.nft_tokens FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = nft_tokens.asset_id));
CREATE POLICY nft_insert_owner ON public.nft_tokens FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = nft_tokens.asset_id AND d.user_id = auth.uid()));
GRANT SELECT, INSERT ON public.nft_tokens TO authenticated;
-- Updates (mint_state, owner_id) are chain-webhook only — revoke client UPDATE.
REVOKE UPDATE, DELETE ON public.nft_tokens FROM authenticated;

ALTER TABLE public.asset_listings
  ADD COLUMN IF NOT EXISTS seaport_order jsonb;

ALTER TABLE public.trades
  ADD COLUMN IF NOT EXISTS chain text DEFAULT 'base',
  ADD COLUMN IF NOT EXISTS contract text;

-- Link-only wallet helper (address validation is client-side checksum).
CREATE OR REPLACE FUNCTION public.link_wallet(
  p_address text,
  p_chain text DEFAULT 'base',
  p_provider text DEFAULT 'coinbase_smart_wallet'
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  addr text := lower(btrim(coalesce(p_address, '')));
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  IF addr !~ '^0x[0-9a-f]{40}$' THEN
    RAISE EXCEPTION 'invalid address' USING ERRCODE = '22023';
  END IF;
  UPDATE public.wallets SET is_primary = false
   WHERE user_id = uid AND chain = coalesce(nullif(p_chain,''),'base');
  INSERT INTO public.wallets (user_id, address, chain, provider, is_primary)
  VALUES (uid, addr, coalesce(nullif(p_chain,''),'base'), p_provider, true)
  ON CONFLICT (user_id, address, chain) DO UPDATE
    SET is_primary = true, provider = EXCLUDED.provider, linked_at = now();
END $$;
REVOKE ALL ON FUNCTION public.link_wallet(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_wallet(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_wallets()
RETURNS SETOF public.wallets
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT * FROM public.wallets WHERE user_id = auth.uid() ORDER BY is_primary DESC, linked_at DESC;
$$;
REVOKE ALL ON FUNCTION public.get_my_wallets() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_wallets() TO authenticated;

COMMIT;
