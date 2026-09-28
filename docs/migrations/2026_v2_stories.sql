-- =============================================================================
-- LOCOLO V2 Phase D — Stories (ephemeral 24h drops)
--
-- CLAUDE: ACTION REQUIRED — this file is NOT applied to prod yet.
-- Owner deferred: paste into Supabase SQL Editor and Run (status §5.11).
-- Until then StoryStore hides the rail (client degrades gracefully).
--
-- Idempotent. Run after V1 social migration.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.stories (
  story_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  asset_id   uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  media_url  text NOT NULL,
  media_type text NOT NULL DEFAULT 'image'
               CHECK (media_type IN ('image', 'video', 'snapshot')),
  caption    text CHECK (caption IS NULL OR char_length(caption) <= 200),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours')
);
CREATE INDEX IF NOT EXISTS stories_active_idx
  ON public.stories (expires_at DESC, created_at DESC)
  WHERE expires_at > now();
CREATE INDEX IF NOT EXISTS stories_user_idx
  ON public.stories (user_id, created_at DESC);

ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stories_select ON public.stories;
DROP POLICY IF EXISTS stories_insert_self ON public.stories;
DROP POLICY IF EXISTS stories_delete_self ON public.stories;

-- Readable while unexpired, and only if the linked asset (if any) is readable
-- under da_select (private/friends). Standalone media stories are public to
-- signed-in users.
CREATE POLICY stories_select ON public.stories FOR SELECT TO authenticated
  USING (
    expires_at > now()
    AND (
      asset_id IS NULL
      OR EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = stories.asset_id)
    )
  );
CREATE POLICY stories_insert_self ON public.stories FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND expires_at > now()
    AND expires_at <= now() + interval '24 hours' + interval '1 minute'
  );
CREATE POLICY stories_delete_self ON public.stories FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.stories TO authenticated;

CREATE TABLE IF NOT EXISTS public.story_views (
  story_id   uuid NOT NULL REFERENCES public.stories(story_id) ON DELETE CASCADE,
  viewer_id  uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  viewed_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, viewer_id)
);
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sv_select_self ON public.story_views;
DROP POLICY IF EXISTS sv_insert_self ON public.story_views;
DROP POLICY IF EXISTS sv_select_author ON public.story_views;
CREATE POLICY sv_select_self ON public.story_views FOR SELECT TO authenticated
  USING (auth.uid() = viewer_id);
CREATE POLICY sv_select_author ON public.story_views FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.stories s
     WHERE s.story_id = story_views.story_id AND s.user_id = auth.uid()));
CREATE POLICY sv_insert_self ON public.story_views FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = viewer_id);
GRANT SELECT, INSERT ON public.story_views TO authenticated;

-- Active stories from people you follow (+ your own), newest first.
CREATE OR REPLACE FUNCTION public.get_story_rail(p_limit int DEFAULT 40)
RETURNS TABLE(
  story_id uuid, user_id uuid, asset_id uuid, media_url text, media_type text,
  caption text, created_at timestamptz, expires_at timestamptz, viewed boolean
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT s.story_id, s.user_id, s.asset_id, s.media_url, s.media_type,
         s.caption, s.created_at, s.expires_at,
         EXISTS (
           SELECT 1 FROM public.story_views v
            WHERE v.story_id = s.story_id AND v.viewer_id = auth.uid()
         ) AS viewed
    FROM public.stories s
   WHERE s.expires_at > now()
     AND (
       s.user_id = auth.uid()
       OR EXISTS (
         SELECT 1 FROM public.follows f
          WHERE f.follower_id = auth.uid()
            AND f.followee_id = s.user_id
            AND f.status = 'accepted')
     )
   ORDER BY (s.user_id = auth.uid()) DESC, s.created_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 40), 100));
$$;
REVOKE ALL ON FUNCTION public.get_story_rail(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_story_rail(int) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_story_viewed(p_story uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.story_views (story_id, viewer_id)
  VALUES (p_story, auth.uid())
  ON CONFLICT DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION public.mark_story_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_story_viewed(uuid) TO authenticated;

-- Optional nightly prune of expired stories (pg_cron or by hand).
CREATE OR REPLACE FUNCTION public.prune_expired_stories()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH gone AS (
    DELETE FROM public.stories WHERE expires_at < now() - interval '7 days'
    RETURNING 1)
  SELECT count(*)::int FROM gone;
$$;
REVOKE ALL ON FUNCTION public.prune_expired_stories() FROM PUBLIC, anon, authenticated;

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.get_story_rail(10);
--   select public.mark_story_viewed('<story uuid>');
-- CLAUDE: apply after mint SQL when convenient — app hides the rail if missing.
-- =============================================================================
