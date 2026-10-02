-- =============================================================================
-- 2026_v3_memories_posts_growth.sql — V3 feedback batch (social layer)
--
--   1. asset_memories  — "memos": photos / clips captured in an AR session with
--                        an asset. Shown on the asset, the owner's profile, the
--                        snap-style viewer and (when shared) the Reels feed.
--   2. memory_likes / memory_views — double-tap like + snap-style "seen".
--   3. user_posts / user_post_likes — user posts that can quote another post,
--                        link an asset or a memory, and carry their own images.
--                        (Not `posts`: that name is the legacy main-app table —
--                        author_id / loop_id NOT NULL, FKs from echoes, hypes,
--                        real_memories — so V3 posts get their own table.)
--   4. get_asset_growth — owner-only daily time series (hypes, explorers,
--                        comments, memories, offers, value) for the
--                        trading-style growth charts.
--   5. update_asset_settings — owner toggles (accepts offers, visibility,
--                        thumbnail, name/description, background audio alert).
--
-- Client degrades gracefully until applied (MemoryStore / PostStore /
-- AssetInsightsStore flip `available = false` on a missing-schema error).
-- Idempotent. Apply in the Supabase SQL editor.
-- Invariant 8 (status §6): read RPCs are SECURITY INVOKER so da_select applies.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Memories
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asset_memories (
  memory_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id       uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  media_url      text NOT NULL,
  media_type     text NOT NULL DEFAULT 'image' CHECK (media_type IN ('image', 'video')),
  thumb_url      text,
  caption        text CHECK (caption IS NULL OR char_length(caption) <= 300),
  visibility     text NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'friends', 'private')),
  shared_to_feed boolean NOT NULL DEFAULT true,
  duration_s     double precision,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS asset_memories_asset_idx ON public.asset_memories (asset_id, created_at DESC);
CREATE INDEX IF NOT EXISTS asset_memories_user_idx  ON public.asset_memories (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS asset_memories_feed_idx  ON public.asset_memories (created_at DESC) WHERE shared_to_feed;

ALTER TABLE public.asset_memories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS am_select ON public.asset_memories;
DROP POLICY IF EXISTS am_insert ON public.asset_memories;
DROP POLICY IF EXISTS am_update ON public.asset_memories;
DROP POLICY IF EXISTS am_delete ON public.asset_memories;
CREATE POLICY am_select ON public.asset_memories FOR SELECT TO authenticated USING (
  user_id = (select auth.uid())
  OR (
    -- the asset itself must be visible to the viewer (da_select applies here)
    EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_memories.asset_id)
    AND (visibility = 'public'
         OR (visibility = 'friends' AND EXISTS (
               SELECT 1 FROM public.follows f
                WHERE f.follower_id = (select auth.uid()) AND f.followee_id = asset_memories.user_id
                  AND f.status = 'accepted')))
    AND NOT EXISTS (SELECT 1 FROM public.user_blocks b
                     WHERE b.blocker_id = (select auth.uid()) AND b.blocked_id = asset_memories.user_id)
  )
);
CREATE POLICY am_insert ON public.asset_memories FOR INSERT TO authenticated WITH CHECK (
  (select auth.uid()) = user_id
  AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_memories.asset_id)
);
CREATE POLICY am_update ON public.asset_memories FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);
-- The memory's author, or the asset's owner (moderating their own asset).
CREATE POLICY am_delete ON public.asset_memories FOR DELETE TO authenticated USING (
  (select auth.uid()) = user_id
  OR EXISTS (SELECT 1 FROM public.digital_assets d
              WHERE d.asset_id = asset_memories.asset_id
                AND coalesce(d.owner_id, d.user_id) = (select auth.uid()))
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.asset_memories TO authenticated;

CREATE TABLE IF NOT EXISTS public.memory_likes (
  memory_id  uuid NOT NULL REFERENCES public.asset_memories(memory_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (memory_id, user_id)
);
CREATE TABLE IF NOT EXISTS public.memory_views (
  memory_id  uuid NOT NULL REFERENCES public.asset_memories(memory_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  seen_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (memory_id, user_id)
);
ALTER TABLE public.memory_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memory_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ml_select ON public.memory_likes;
DROP POLICY IF EXISTS ml_write  ON public.memory_likes;
DROP POLICY IF EXISTS ml_delete ON public.memory_likes;
DROP POLICY IF EXISTS mv_self   ON public.memory_views;
CREATE POLICY ml_select ON public.memory_likes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.asset_memories m WHERE m.memory_id = memory_likes.memory_id));
CREATE POLICY ml_write ON public.memory_likes FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id
              AND EXISTS (SELECT 1 FROM public.asset_memories m WHERE m.memory_id = memory_likes.memory_id));
CREATE POLICY ml_delete ON public.memory_likes FOR DELETE TO authenticated USING ((select auth.uid()) = user_id);
CREATE POLICY mv_self ON public.memory_views FOR ALL TO authenticated
  USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);
CREATE INDEX IF NOT EXISTS memory_likes_user_idx ON public.memory_likes (user_id);
CREATE INDEX IF NOT EXISTS memory_views_user_idx ON public.memory_views (user_id);
GRANT SELECT, INSERT, DELETE ON public.memory_likes TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.memory_views TO authenticated;

-- One row per memory, decorated for the UI. Shared by every memory RPC.
-- p_scope: 'feed' (shared_to_feed, newest first), 'asset', 'user'.
CREATE OR REPLACE FUNCTION public.get_memories(
  p_scope  text,
  p_id     uuid DEFAULT NULL,
  p_limit  int  DEFAULT 30,
  p_before timestamptz DEFAULT NULL
)
RETURNS TABLE(
  memory_id uuid, asset_id uuid, user_id uuid, media_url text, media_type text,
  thumb_url text, caption text, visibility text, shared_to_feed boolean,
  duration_s double precision, created_at timestamptz,
  like_count int, liked_by_me boolean, seen_by_me boolean,
  asset_name text, asset_thumb_url text, asset_owner_id uuid,
  latitude double precision, longitude double precision
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, extensions AS $$
  SELECT m.memory_id, m.asset_id, m.user_id, m.media_url, m.media_type,
         m.thumb_url, m.caption, m.visibility, m.shared_to_feed,
         m.duration_s, m.created_at,
         (SELECT count(*)::int FROM public.memory_likes l WHERE l.memory_id = m.memory_id),
         EXISTS (SELECT 1 FROM public.memory_likes l WHERE l.memory_id = m.memory_id AND l.user_id = (select auth.uid())),
         EXISTS (SELECT 1 FROM public.memory_views v WHERE v.memory_id = m.memory_id AND v.user_id = (select auth.uid())),
         d.name, d.thumb_url, coalesce(d.owner_id, d.user_id),
         loc.latitude, loc.longitude
    FROM public.asset_memories m
    JOIN public.digital_assets d ON d.asset_id = m.asset_id
    LEFT JOIN public.locations loc ON loc.location_id = d.location_id
   WHERE (p_before IS NULL OR m.created_at < p_before)
     AND CASE p_scope
           WHEN 'feed'  THEN m.shared_to_feed
           WHEN 'asset' THEN m.asset_id = p_id
           WHEN 'user'  THEN m.user_id = p_id
           ELSE false
         END
   ORDER BY m.created_at DESC
   LIMIT least(greatest(p_limit, 1), 100);
$$;
REVOKE ALL ON FUNCTION public.get_memories(text, uuid, int, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_memories(text, uuid, int, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Posts (quote posts + linked asset / memory + own media)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_posts (
  post_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  body             text CHECK (body IS NULL OR char_length(body) <= 2000),
  media            jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{ "url": "...", "type": "image"|"video" }]
  linked_post_id   uuid REFERENCES public.user_posts(post_id) ON DELETE SET NULL,
  linked_asset_id  uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  linked_memory_id uuid REFERENCES public.asset_memories(memory_id) ON DELETE SET NULL,
  visibility       text NOT NULL DEFAULT 'public' CHECK (visibility IN ('public', 'friends', 'private')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (coalesce(char_length(btrim(body)), 0) > 0
         OR jsonb_array_length(media) > 0
         OR linked_post_id IS NOT NULL OR linked_asset_id IS NOT NULL OR linked_memory_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS user_posts_user_idx ON public.user_posts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS user_posts_feed_idx ON public.user_posts (created_at DESC);
CREATE INDEX IF NOT EXISTS user_posts_linked_post_idx   ON public.user_posts (linked_post_id)   WHERE linked_post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS user_posts_linked_asset_idx  ON public.user_posts (linked_asset_id)  WHERE linked_asset_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS user_posts_linked_memory_idx ON public.user_posts (linked_memory_id) WHERE linked_memory_id IS NOT NULL;

ALTER TABLE public.user_posts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS up_select ON public.user_posts;
DROP POLICY IF EXISTS up_insert ON public.user_posts;
DROP POLICY IF EXISTS up_update ON public.user_posts;
DROP POLICY IF EXISTS up_delete ON public.user_posts;
CREATE POLICY up_select ON public.user_posts FOR SELECT TO authenticated USING (
  user_id = (select auth.uid())
  OR ((visibility = 'public'
       OR (visibility = 'friends' AND EXISTS (
             SELECT 1 FROM public.follows f
              WHERE f.follower_id = (select auth.uid()) AND f.followee_id = user_posts.user_id
                AND f.status = 'accepted')))
      AND NOT EXISTS (SELECT 1 FROM public.user_blocks b
                       WHERE b.blocker_id = (select auth.uid()) AND b.blocked_id = user_posts.user_id))
);
CREATE POLICY up_insert ON public.user_posts FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY up_update ON public.user_posts FOR UPDATE TO authenticated
  USING ((select auth.uid()) = user_id) WITH CHECK ((select auth.uid()) = user_id);
CREATE POLICY up_delete ON public.user_posts FOR DELETE TO authenticated USING ((select auth.uid()) = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_posts TO authenticated;

CREATE TABLE IF NOT EXISTS public.user_post_likes (
  post_id    uuid NOT NULL REFERENCES public.user_posts(post_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
ALTER TABLE public.user_post_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS upl_select ON public.user_post_likes;
DROP POLICY IF EXISTS upl_insert ON public.user_post_likes;
DROP POLICY IF EXISTS upl_delete ON public.user_post_likes;
CREATE POLICY upl_select ON public.user_post_likes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.user_posts p WHERE p.post_id = user_post_likes.post_id));
CREATE POLICY upl_insert ON public.user_post_likes FOR INSERT TO authenticated
  WITH CHECK ((select auth.uid()) = user_id AND EXISTS (SELECT 1 FROM public.user_posts p WHERE p.post_id = user_post_likes.post_id));
CREATE POLICY upl_delete ON public.user_post_likes FOR DELETE TO authenticated USING ((select auth.uid()) = user_id);
CREATE INDEX IF NOT EXISTS user_post_likes_user_idx ON public.user_post_likes (user_id);
GRANT SELECT, INSERT, DELETE ON public.user_post_likes TO authenticated;

-- p_scope: 'feed' | 'user' | 'one' (p_id = post id)
CREATE OR REPLACE FUNCTION public.get_posts(
  p_scope  text,
  p_id     uuid DEFAULT NULL,
  p_limit  int  DEFAULT 30,
  p_before timestamptz DEFAULT NULL
)
RETURNS TABLE(
  post_id uuid, user_id uuid, body text, media jsonb,
  linked_post_id uuid, linked_asset_id uuid, linked_memory_id uuid,
  visibility text, created_at timestamptz,
  like_count int, liked_by_me boolean, quote_count int
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT p.post_id, p.user_id, p.body, p.media,
         p.linked_post_id, p.linked_asset_id, p.linked_memory_id,
         p.visibility, p.created_at,
         (SELECT count(*)::int FROM public.user_post_likes l WHERE l.post_id = p.post_id),
         EXISTS (SELECT 1 FROM public.user_post_likes l WHERE l.post_id = p.post_id AND l.user_id = (select auth.uid())),
         (SELECT count(*)::int FROM public.user_posts q WHERE q.linked_post_id = p.post_id)
    FROM public.user_posts p
   WHERE (p_before IS NULL OR p.created_at < p_before)
     AND CASE p_scope
           WHEN 'feed' THEN true
           WHEN 'user' THEN p.user_id = p_id
           WHEN 'one'  THEN p.post_id = p_id
           ELSE false
         END
   ORDER BY p.created_at DESC
   LIMIT least(greatest(p_limit, 1), 100);
$$;
REVOKE ALL ON FUNCTION public.get_posts(text, uuid, int, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_posts(text, uuid, int, timestamptz) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Asset growth series (owner-only analytics)
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER because asset_hype / asset_views rows of other users aren't
-- readable by the owner under RLS; the function re-checks ownership itself.
CREATE OR REPLACE FUNCTION public.get_asset_growth(p_asset uuid, p_days int DEFAULT 90)
RETURNS TABLE(
  day date, hypes int, explorers int, comments int, memories int,
  offers int, value numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner uuid;
  start_day date := (now() - make_interval(days => least(greatest(p_days, 7), 730)))::date;
BEGIN
  SELECT coalesce(d.owner_id, d.user_id) INTO owner FROM public.digital_assets d WHERE d.asset_id = p_asset;
  IF owner IS NULL OR owner IS DISTINCT FROM (select auth.uid()) THEN
    RAISE EXCEPTION 'only the owner can view insights' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH days AS (
    SELECT generate_series(start_day, now()::date, interval '1 day')::date AS day
  )
  SELECT
    days.day,
    (SELECT count(*)::int FROM public.asset_hype h     WHERE h.asset_id = p_asset AND h.created_at::date <= days.day),
    (SELECT count(*)::int FROM public.asset_views v    WHERE v.asset_id = p_asset AND v.seen_at::date    <= days.day),
    (SELECT count(*)::int FROM public.asset_comments c WHERE c.asset_id = p_asset AND c.created_at::date <= days.day),
    (SELECT count(*)::int FROM public.asset_memories m WHERE m.asset_id = p_asset AND m.created_at::date <= days.day),
    (SELECT count(*)::int FROM public.offers o         WHERE o.asset_id = p_asset AND o.created_at::date <= days.day),
    coalesce(
      (SELECT t.price FROM public.trades t
        WHERE t.asset_id = p_asset AND t.settled_at::date <= days.day
        ORDER BY t.settled_at DESC LIMIT 1),
      (SELECT max(o.amount) FROM public.offers o
        WHERE o.asset_id = p_asset AND o.created_at::date <= days.day
          AND o.status IN ('pending', 'accepted')),
      (SELECT d.current_value FROM public.digital_assets d WHERE d.asset_id = p_asset)
    )
  FROM days
  ORDER BY days.day;
END $$;
REVOKE ALL ON FUNCTION public.get_asset_growth(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_growth(uuid, int) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. Owner settings
-- ---------------------------------------------------------------------------
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS alert_audio_url  text,          -- played by background AR mode on approach
  ADD COLUMN IF NOT EXISTS alert_radius_m   double precision DEFAULT 60;

-- Owner (current holder) controls trading + visibility; the original creator
-- controls presentation (name, description, thumbnail, alert audio).
-- NULL params are left unchanged.
CREATE OR REPLACE FUNCTION public.update_asset_settings(
  p_asset          uuid,
  p_accepts_offers boolean DEFAULT NULL,
  p_visibility     text    DEFAULT NULL,
  p_name           text    DEFAULT NULL,
  p_description    text    DEFAULT NULL,
  p_thumb_url      text    DEFAULT NULL,
  p_alert_audio_url text   DEFAULT NULL,
  p_alert_radius_m double precision DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE d public.digital_assets%ROWTYPE;
BEGIN
  SELECT * INTO d FROM public.digital_assets WHERE asset_id = p_asset FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'asset not found' USING ERRCODE = 'P0002'; END IF;

  IF (p_accepts_offers IS NOT NULL OR p_visibility IS NOT NULL)
     AND coalesce(d.owner_id, d.user_id) IS DISTINCT FROM (select auth.uid()) THEN
    RAISE EXCEPTION 'only the owner can change trading or visibility' USING ERRCODE = '42501';
  END IF;
  IF (p_name IS NOT NULL OR p_description IS NOT NULL OR p_thumb_url IS NOT NULL
      OR p_alert_audio_url IS NOT NULL OR p_alert_radius_m IS NOT NULL)
     AND d.user_id IS DISTINCT FROM (select auth.uid()) THEN
    RAISE EXCEPTION 'only the creator can edit the presentation' USING ERRCODE = '42501';
  END IF;
  IF p_visibility IS NOT NULL AND p_visibility NOT IN ('public', 'friends', 'private') THEN
    RAISE EXCEPTION 'invalid visibility' USING ERRCODE = '22023';
  END IF;

  UPDATE public.digital_assets SET
    accepts_offers  = coalesce(p_accepts_offers, accepts_offers),
    visibility      = coalesce(p_visibility, visibility),
    name            = coalesce(nullif(btrim(p_name), ''), name),
    description     = coalesce(p_description, description),
    thumb_url       = coalesce(p_thumb_url, thumb_url),
    alert_audio_url = CASE WHEN p_alert_audio_url = '' THEN NULL
                           ELSE coalesce(p_alert_audio_url, alert_audio_url) END,
    alert_radius_m  = CASE WHEN p_alert_radius_m IS NULL THEN alert_radius_m
                           ELSE least(greatest(p_alert_radius_m, 10), 500) END
   WHERE asset_id = p_asset;
END $$;
REVOKE ALL ON FUNCTION public.update_asset_settings(uuid, boolean, text, text, text, text, text, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_asset_settings(uuid, boolean, text, text, text, text, text, double precision) TO authenticated;

-- Background AR mode: the nearby fetch needs the alert audio without widening
-- the 42-column DigitalAsset contract (invariant 1), so it's a separate read.
CREATE OR REPLACE FUNCTION public.get_asset_alerts(p_assets uuid[])
RETURNS TABLE(asset_id uuid, alert_audio_url text, alert_radius_m double precision)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT d.asset_id, d.alert_audio_url, coalesce(d.alert_radius_m, 60)
    FROM public.digital_assets d
   WHERE d.asset_id = ANY(p_assets) AND d.alert_audio_url IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.get_asset_alerts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_asset_alerts(uuid[]) TO authenticated;

-- Supabase's default privileges grant anon ALL on new public tables. RLS
-- already returns nothing to anon (policies are TO authenticated), but revoke
-- so the tables aren't in anon's GraphQL schema either (advisor 0026).
REVOKE ALL ON public.asset_memories, public.memory_likes, public.memory_views,
              public.user_posts, public.user_post_likes FROM anon;

COMMIT;
