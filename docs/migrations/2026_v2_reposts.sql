-- =============================================================================
-- LOCOLO V2 Phase D — Reposts / Re-drop
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.15).
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.reposts (
  repost_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  caption    text CHECK (caption IS NULL OR char_length(caption) <= 200),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, asset_id)
);
CREATE INDEX IF NOT EXISTS reposts_asset_idx ON public.reposts (asset_id, created_at DESC);
CREATE INDEX IF NOT EXISTS reposts_user_idx ON public.reposts (user_id, created_at DESC);

ALTER TABLE public.reposts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reposts_select ON public.reposts;
DROP POLICY IF EXISTS reposts_insert_self ON public.reposts;
DROP POLICY IF EXISTS reposts_delete_self ON public.reposts;

CREATE POLICY reposts_select ON public.reposts FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = reposts.asset_id));
CREATE POLICY reposts_insert_self ON public.reposts FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = reposts.asset_id)
  );
CREATE POLICY reposts_delete_self ON public.reposts FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.reposts TO authenticated;

CREATE OR REPLACE FUNCTION public.get_repost_counts(p_assets uuid[])
RETURNS TABLE(asset_id uuid, repost_count integer)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT r.asset_id, count(*)::int
    FROM public.reposts r
   WHERE r.asset_id = ANY(p_assets)
   GROUP BY r.asset_id;
$$;
REVOKE ALL ON FUNCTION public.get_repost_counts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_repost_counts(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_repost(p_asset uuid, p_caption text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  now_on boolean;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  IF EXISTS (SELECT 1 FROM public.reposts WHERE user_id = uid AND asset_id = p_asset) THEN
    DELETE FROM public.reposts WHERE user_id = uid AND asset_id = p_asset;
    now_on := false;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = p_asset) THEN
      RAISE EXCEPTION 'asset not visible' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.reposts (user_id, asset_id, caption)
    VALUES (uid, p_asset, nullif(btrim(coalesce(p_caption, '')), ''));
    now_on := true;
  END IF;
  RETURN now_on;
END $$;
REVOKE ALL ON FUNCTION public.toggle_repost(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_repost(uuid, text) TO authenticated;

COMMIT;
