-- =============================================================================
-- LOCOLO V2 Phase D — Explorer Passport progress + weekly leaderboard
--
-- CLAUDE: ACTION REQUIRED — this file is NOT applied to prod yet.
-- Owner deferred: paste into Supabase SQL Editor and Run (status §5.14).
-- Until then ProgressStore keeps using client-only Passport (no sync).
--
-- Idempotent. XP/streak/level off-chain. Client Passport still derives from
-- local activity; this table is the durable cross-device source of truth.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.user_progress (
  user_id      uuid PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
  xp           int NOT NULL DEFAULT 0 CHECK (xp >= 0),
  level        int NOT NULL DEFAULT 1 CHECK (level >= 1),
  streak_days  int NOT NULL DEFAULT 0 CHECK (streak_days >= 0),
  last_active  date,
  discoveries  int NOT NULL DEFAULT 0 CHECK (discoveries >= 0),
  created_count int NOT NULL DEFAULT 0 CHECK (created_count >= 0),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_progress ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS up_select ON public.user_progress;
DROP POLICY IF EXISTS up_insert_self ON public.user_progress;
DROP POLICY IF EXISTS up_update_self ON public.user_progress;
-- Public read (levels/streaks on profiles); only owner writes via RPC.
CREATE POLICY up_select ON public.user_progress FOR SELECT TO authenticated USING (true);
CREATE POLICY up_insert_self ON public.user_progress FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY up_update_self ON public.user_progress FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT ON public.user_progress TO authenticated;
-- Writes go through award_progress (SECURITY DEFINER).
REVOKE INSERT, UPDATE, DELETE ON public.user_progress FROM authenticated;

CREATE OR REPLACE FUNCTION public._level_for_xp(p_xp int)
RETURNS int LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_xp >= 6000 THEN 6
    WHEN p_xp >= 3000 THEN 5
    WHEN p_xp >= 1500 THEN 4
    WHEN p_xp >= 750  THEN 3
    WHEN p_xp >= 250  THEN 2
    ELSE 1
  END;
$$;

-- Award XP for an action; updates streak (calendar day in UTC).
-- p_kind: discover | create | explore | hype_received | daily_open
CREATE OR REPLACE FUNCTION public.award_progress(p_kind text, p_amount int DEFAULT NULL)
RETURNS public.user_progress
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  amt int;
  today date := (timezone('utc', now()))::date;
  row public.user_progress;
  new_streak int;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;

  amt := coalesce(p_amount, CASE p_kind
    WHEN 'discover' THEN 50
    WHEN 'create' THEN 100
    WHEN 'explore' THEN 10
    WHEN 'hype_received' THEN 5
    WHEN 'daily_open' THEN 5
    ELSE 0
  END);
  IF amt < 0 THEN amt := 0; END IF;

  INSERT INTO public.user_progress (user_id, xp, level, streak_days, last_active, discoveries, created_count)
  VALUES (uid, 0, 1, 0, NULL, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO row FROM public.user_progress WHERE user_id = uid FOR UPDATE;

  IF row.last_active IS NULL OR row.last_active < today - 1 THEN
    new_streak := 1;
  ELSIF row.last_active = today THEN
    new_streak := row.streak_days; -- already counted today
  ELSE
    new_streak := row.streak_days + 1; -- yesterday → continue
  END IF;

  UPDATE public.user_progress SET
    xp = row.xp + amt,
    level = public._level_for_xp(row.xp + amt),
    streak_days = new_streak,
    last_active = today,
    discoveries = row.discoveries + CASE WHEN p_kind = 'discover' THEN 1 ELSE 0 END,
    created_count = row.created_count + CASE WHEN p_kind = 'create' THEN 1 ELSE 0 END,
    updated_at = now()
  WHERE user_id = uid
  RETURNING * INTO row;

  RETURN row;
END $$;
REVOKE ALL ON FUNCTION public.award_progress(text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_progress(text, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_my_progress()
RETURNS public.user_progress
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM public.user_progress WHERE user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.get_my_progress() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_progress() TO authenticated;

-- Weekly leaderboard by XP (top N). Optional: filter to following later.
CREATE OR REPLACE FUNCTION public.get_xp_leaderboard(p_limit int DEFAULT 20)
RETURNS TABLE(
  user_id uuid, xp int, level int, streak_days int,
  username text, name text, avatar_url text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT p.user_id, p.xp, p.level, p.streak_days,
         u.username, u.name, u.avatar_url
    FROM public.user_progress p
    JOIN public.users u ON u.user_id = p.user_id
   ORDER BY p.xp DESC, p.updated_at ASC
   LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
$$;
REVOKE ALL ON FUNCTION public.get_xp_leaderboard(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_xp_leaderboard(int) TO authenticated;

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.award_progress('daily_open');
--   select * from public.get_xp_leaderboard(10);
-- CLAUDE: apply when convenient — client Passport still works offline.
-- =============================================================================
