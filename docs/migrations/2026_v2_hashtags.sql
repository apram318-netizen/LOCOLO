-- =============================================================================
-- LOCOLO V2 Phase D — Hashtags / topics
--
-- CLAUDE: ACTION REQUIRED — this file is NOT applied to prod yet.
-- Owner deferred: paste into Supabase SQL Editor and Run (status §5.13).
-- Until then TagStore hides trending tags (client degrades gracefully).
--
-- Idempotent. Run after V1 social migration.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.tags (
  tag_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       text NOT NULL UNIQUE
               CHECK (slug ~ '^[a-z0-9_]{2,32}$'),
  label      text NOT NULL CHECK (char_length(btrim(label)) BETWEEN 2 AND 40),
  use_count  int  NOT NULL DEFAULT 0 CHECK (use_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tags_use_count_idx ON public.tags (use_count DESC, slug);

ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tags_select ON public.tags;
DROP POLICY IF EXISTS tags_insert_auth ON public.tags;
CREATE POLICY tags_select ON public.tags FOR SELECT TO authenticated USING (true);
-- Inserts go through set_asset_tags (SECURITY DEFINER); keep direct insert for
-- authenticated as a fallback when creating a brand-new slug mid-flow.
CREATE POLICY tags_insert_auth ON public.tags FOR INSERT TO authenticated
  WITH CHECK (true);
GRANT SELECT, INSERT ON public.tags TO authenticated;

CREATE TABLE IF NOT EXISTS public.asset_tags (
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  tag_id     uuid NOT NULL REFERENCES public.tags(tag_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, tag_id)
);
CREATE INDEX IF NOT EXISTS asset_tags_tag_idx ON public.asset_tags (tag_id);

ALTER TABLE public.asset_tags ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS at_select ON public.asset_tags;
DROP POLICY IF EXISTS at_insert_owner ON public.asset_tags;
DROP POLICY IF EXISTS at_delete_owner ON public.asset_tags;

CREATE POLICY at_select ON public.asset_tags FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_tags.asset_id));
CREATE POLICY at_insert_owner ON public.asset_tags FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_tags.asset_id AND d.user_id = auth.uid()));
CREATE POLICY at_delete_owner ON public.asset_tags FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_tags.asset_id AND d.user_id = auth.uid()));

GRANT SELECT, INSERT, DELETE ON public.asset_tags TO authenticated;

-- Normalize: lowercase, strip leading #, non [a-z0-9_] → underscore, clamp 2–32.
CREATE OR REPLACE FUNCTION public.normalize_tag_slug(p_raw text)
RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT nullif(
    left(
      regexp_replace(
        lower(regexp_replace(btrim(coalesce(p_raw, '')), '^#+', '')),
        '[^a-z0-9_]+', '_', 'g'),
      32),
    '');
$$;

-- Replace all tags on an asset (owner only). Accepts raw labels/slugs.
CREATE OR REPLACE FUNCTION public.set_asset_tags(p_asset uuid, p_tags text[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  raw text;
  s   text;
  tid uuid;
  keep uuid[] := ARRAY[]::uuid[];
  touched uuid[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = p_asset AND d.user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'not owner' USING ERRCODE = '42501';
  END IF;

  SELECT coalesce(array_agg(tag_id), ARRAY[]::uuid[])
    INTO touched
    FROM public.asset_tags
   WHERE asset_id = p_asset;

  FOREACH raw IN ARRAY coalesce(p_tags, ARRAY[]::text[]) LOOP
    s := public.normalize_tag_slug(raw);
    IF s IS NULL OR char_length(s) < 2 THEN CONTINUE; END IF;
    INSERT INTO public.tags (slug, label)
    VALUES (s, s)
    ON CONFLICT (slug) DO NOTHING;
    SELECT tag_id INTO tid FROM public.tags WHERE slug = s;
    IF tid IS NULL THEN CONTINUE; END IF;
    INSERT INTO public.asset_tags (asset_id, tag_id)
    VALUES (p_asset, tid)
    ON CONFLICT DO NOTHING;
    keep := array_append(keep, tid);
  END LOOP;

  DELETE FROM public.asset_tags
   WHERE asset_id = p_asset
     AND (cardinality(keep) = 0 OR NOT (tag_id = ANY (keep)));

  UPDATE public.tags t
     SET use_count = (SELECT count(*)::int FROM public.asset_tags a WHERE a.tag_id = t.tag_id)
   WHERE t.tag_id = ANY (touched || keep);
END $$;
REVOKE ALL ON FUNCTION public.set_asset_tags(uuid, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_asset_tags(uuid, text[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_trending_tags(p_limit int DEFAULT 20)
RETURNS TABLE(slug text, label text, use_count int)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT t.slug, t.label, t.use_count
    FROM public.tags t
   WHERE t.use_count > 0
   ORDER BY t.use_count DESC, t.slug
   LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
$$;
REVOKE ALL ON FUNCTION public.get_trending_tags(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_trending_tags(int) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_asset_tags(p_asset uuid)
RETURNS TABLE(slug text, label text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT t.slug, t.label
    FROM public.asset_tags a
    JOIN public.tags t ON t.tag_id = a.tag_id
   WHERE a.asset_id = p_asset
   ORDER BY t.slug;
$$;
REVOKE ALL ON FUNCTION public.get_asset_tags(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_tags(uuid) TO authenticated;

-- Asset ids for a tag slug (newest first).
CREATE OR REPLACE FUNCTION public.get_assets_by_tag(p_slug text, p_limit int DEFAULT 40)
RETURNS TABLE(asset_id uuid)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT a.asset_id
    FROM public.asset_tags a
    JOIN public.tags t ON t.tag_id = a.tag_id
   WHERE t.slug = public.normalize_tag_slug(p_slug)
     AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = a.asset_id)
   ORDER BY a.created_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 40), 100));
$$;
REVOKE ALL ON FUNCTION public.get_assets_by_tag(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assets_by_tag(text, int) TO authenticated;

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.get_trending_tags(10);
-- CLAUDE: apply when convenient — app hides tag UI if migration missing.
-- =============================================================================
