-- =============================================================================
-- Locolo AR — Social layer v2: comments + comment moderation
--
-- Run AFTER docs/migrations/2026_ar_safety_and_hardening.sql (depends on its
-- visibility-enforcing da_select policy and on content_reports).
-- One transaction, idempotent (safe to re-run).
--
-- The app degrades gracefully before this runs: the comment sheet shows
-- "Comments are coming soon" and counts stay hidden.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. asset_comments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.asset_comments (
  comment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id)          ON DELETE CASCADE,
  body       text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 500),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS asset_comments_asset_idx ON public.asset_comments (asset_id, created_at DESC);
CREATE INDEX IF NOT EXISTS asset_comments_user_idx  ON public.asset_comments (user_id);

ALTER TABLE public.asset_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ac_select      ON public.asset_comments;
DROP POLICY IF EXISTS ac_insert_self ON public.asset_comments;
DROP POLICY IF EXISTS ac_delete      ON public.asset_comments;

-- Readable iff the asset itself is readable to the caller: the subquery runs
-- under the caller's RLS, so da_select's private/friends rules carry over.
CREATE POLICY ac_select ON public.asset_comments FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_comments.asset_id));

-- Comment as yourself, only on assets you can see, and not on creators who
-- have blocked you.
CREATE POLICY ac_insert_self ON public.asset_comments FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_comments.asset_id)
    AND NOT EXISTS (
      SELECT 1 FROM public.user_blocks b
      JOIN public.digital_assets d ON d.asset_id = asset_comments.asset_id
      WHERE b.blocker_id = d.user_id AND b.blocked_id = auth.uid())
  );

-- Authors delete their own comments; creators moderate their own assets.
CREATE POLICY ac_delete ON public.asset_comments FOR DELETE TO authenticated
  USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM public.digital_assets d
               WHERE d.asset_id = asset_comments.asset_id AND d.user_id = auth.uid())
  );

GRANT SELECT, INSERT, DELETE ON public.asset_comments TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Batched comment counts for feed cards (SECURITY INVOKER → RLS applies)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_comment_counts(p_assets uuid[])
RETURNS TABLE(asset_id uuid, comment_count integer)
LANGUAGE sql STABLE AS $$
  SELECT c.asset_id, count(*)::int
    FROM public.asset_comments c
   WHERE c.asset_id = ANY(p_assets)
   GROUP BY c.asset_id;
$$;
REVOKE ALL ON FUNCTION public.get_comment_counts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_comment_counts(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Reports can target a comment
-- ---------------------------------------------------------------------------
ALTER TABLE public.content_reports
  ADD COLUMN IF NOT EXISTS comment_id uuid REFERENCES public.asset_comments(comment_id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 4. Account deletion also removes the user's comments
--    (ON DELETE CASCADE from users covers it; listed for clarity.)
-- ---------------------------------------------------------------------------

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.asset_comments limit 1;                 -- table exists
--   select * from public.get_comment_counts(array[]::uuid[]);    -- returns 0 rows
-- Moderation:
--   select r.*, c.body from public.content_reports r
--     left join public.asset_comments c using (comment_id)
--    where r.status = 'open' order by r.created_at;
-- =============================================================================
