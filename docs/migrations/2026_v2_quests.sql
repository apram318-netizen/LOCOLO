-- =============================================================================
-- LOCOLO V2 Phase D — Weekly quests (Passport)
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.17).
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.quests (
  quest_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  title       text NOT NULL,
  detail      text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('discover','create','hype','explore','repost')),
  goal        int  NOT NULL CHECK (goal > 0),
  xp_reward   int  NOT NULL DEFAULT 25 CHECK (xp_reward >= 0),
  active      boolean NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS public.user_quests (
  user_id     uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  quest_id    uuid NOT NULL REFERENCES public.quests(quest_id) ON DELETE CASCADE,
  week_start  date NOT NULL,  -- Monday UTC of the week
  progress    int  NOT NULL DEFAULT 0 CHECK (progress >= 0),
  completed   boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  PRIMARY KEY (user_id, quest_id, week_start)
);

ALTER TABLE public.quests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_quests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS quests_select ON public.quests;
DROP POLICY IF EXISTS uq_select_self ON public.user_quests;
CREATE POLICY quests_select ON public.quests FOR SELECT TO authenticated USING (active);
CREATE POLICY uq_select_self ON public.user_quests FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
GRANT SELECT ON public.quests TO authenticated;
GRANT SELECT ON public.user_quests TO authenticated;

INSERT INTO public.quests (slug, title, detail, kind, goal, xp_reward) VALUES
  ('discover_3', 'Find 3 drops', 'Walk up to 3 AR creations this week', 'discover', 3, 40),
  ('create_1', 'Drop something', 'Publish 1 AR asset this week', 'create', 1, 60),
  ('hype_5', 'Spread the hype', 'Hype 5 creations this week', 'hype', 5, 30),
  ('explore_5', 'Open 5 pieces', 'Explore 5 assets in detail this week', 'explore', 5, 25),
  ('repost_2', 'Re-drop 2', 'Re-drop 2 pieces to your followers', 'repost', 2, 35)
ON CONFLICT (slug) DO NOTHING;

CREATE OR REPLACE FUNCTION public._quest_week_start(p_ts timestamptz DEFAULT now())
RETURNS date LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT (date_trunc('week', p_ts AT TIME ZONE 'UTC'))::date;
$$;

-- Bump weekly quest progress for the signed-in user; awards XP on complete.
CREATE OR REPLACE FUNCTION public.bump_quest(p_kind text, p_delta int DEFAULT 1)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  wk date := public._quest_week_start();
  q record;
  new_prog int;
BEGIN
  IF uid IS NULL THEN RETURN; END IF;
  FOR q IN SELECT * FROM public.quests WHERE active AND kind = p_kind LOOP
    INSERT INTO public.user_quests (user_id, quest_id, week_start, progress)
    VALUES (uid, q.quest_id, wk, 0)
    ON CONFLICT DO NOTHING;

    UPDATE public.user_quests u
       SET progress = LEAST(q.goal, u.progress + greatest(p_delta, 0))
     WHERE u.user_id = uid AND u.quest_id = q.quest_id AND u.week_start = wk
       AND NOT u.completed
    RETURNING progress INTO new_prog;

    IF new_prog IS NOT NULL AND new_prog >= q.goal THEN
      UPDATE public.user_quests
         SET completed = true, completed_at = now(), progress = q.goal
       WHERE user_id = uid AND quest_id = q.quest_id AND week_start = wk
         AND NOT completed;
      PERFORM public.award_progress('daily_open', q.xp_reward);
    END IF;
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.bump_quest(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.bump_quest(text, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_week_quests()
RETURNS TABLE(
  quest_id uuid, slug text, title text, detail text, kind text,
  goal int, xp_reward int, progress int, completed boolean
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT q.quest_id, q.slug, q.title, q.detail, q.kind, q.goal, q.xp_reward,
         coalesce(u.progress, 0), coalesce(u.completed, false)
    FROM public.quests q
    LEFT JOIN public.user_quests u
      ON u.quest_id = q.quest_id
     AND u.user_id = auth.uid()
     AND u.week_start = public._quest_week_start()
   WHERE q.active
   ORDER BY q.slug;
$$;
REVOKE ALL ON FUNCTION public.get_my_week_quests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_week_quests() TO authenticated;

COMMIT;
