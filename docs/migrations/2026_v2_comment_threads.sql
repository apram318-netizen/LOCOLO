-- =============================================================================
-- LOCOLO V2 Phase D — Threaded comment replies + comment likes
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.16).
-- Client degrades: replies/likes stay hidden until applied.
-- =============================================================================

BEGIN;

ALTER TABLE public.asset_comments
  ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES public.asset_comments(comment_id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS asset_comments_parent_idx
  ON public.asset_comments (parent_id, created_at ASC)
  WHERE parent_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.comment_likes (
  comment_id uuid NOT NULL REFERENCES public.asset_comments(comment_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);
CREATE INDEX IF NOT EXISTS comment_likes_user_idx ON public.comment_likes (user_id);

ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cl_select ON public.comment_likes;
DROP POLICY IF EXISTS cl_insert_self ON public.comment_likes;
DROP POLICY IF EXISTS cl_delete_self ON public.comment_likes;

CREATE POLICY cl_select ON public.comment_likes FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.asset_comments c WHERE c.comment_id = comment_likes.comment_id));
CREATE POLICY cl_insert_self ON public.comment_likes FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.asset_comments c WHERE c.comment_id = comment_likes.comment_id)
  );
CREATE POLICY cl_delete_self ON public.comment_likes FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT, INSERT, DELETE ON public.comment_likes TO authenticated;

CREATE OR REPLACE FUNCTION public.get_comment_like_counts(p_comments uuid[])
RETURNS TABLE(comment_id uuid, like_count integer, liked_by_me boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT c.comment_id,
         count(l.user_id)::int AS like_count,
         bool_or(l.user_id = auth.uid()) AS liked_by_me
    FROM unnest(p_comments) AS c(comment_id)
    LEFT JOIN public.comment_likes l ON l.comment_id = c.comment_id
   GROUP BY c.comment_id;
$$;
REVOKE ALL ON FUNCTION public.get_comment_like_counts(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_comment_like_counts(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_comment_like(p_comment uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  now_on boolean;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  IF EXISTS (SELECT 1 FROM public.comment_likes WHERE comment_id = p_comment AND user_id = uid) THEN
    DELETE FROM public.comment_likes WHERE comment_id = p_comment AND user_id = uid;
    now_on := false;
  ELSE
    INSERT INTO public.comment_likes (comment_id, user_id) VALUES (p_comment, uid);
    now_on := true;
  END IF;
  RETURN now_on;
END $$;
REVOKE ALL ON FUNCTION public.toggle_comment_like(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_comment_like(uuid) TO authenticated;

COMMIT;
