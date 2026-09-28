-- =============================================================================
-- LOCOLO V2 Phase D Tier 2–3 — Remixes, collabs, reactions, polls, presence,
-- events, close friends, mutes, comment moderation
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.20).
-- Apply after V1 social + §5.11–§5.17. Idempotent.
-- =============================================================================

BEGIN;

-- Remix chain (avoids expanding 41-col DigitalAsset RPCs)
CREATE TABLE IF NOT EXISTS public.asset_remixes (
  asset_id        uuid PRIMARY KEY REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  parent_asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (asset_id <> parent_asset_id)
);
CREATE INDEX IF NOT EXISTS asset_remixes_parent_idx ON public.asset_remixes (parent_asset_id);
ALTER TABLE public.asset_remixes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS remix_select ON public.asset_remixes;
DROP POLICY IF EXISTS remix_insert_owner ON public.asset_remixes;
CREATE POLICY remix_select ON public.asset_remixes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_remixes.asset_id));
CREATE POLICY remix_insert_owner ON public.asset_remixes FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_remixes.asset_id AND d.user_id = auth.uid()));
GRANT SELECT, INSERT ON public.asset_remixes TO authenticated;

-- Collab credits (royalty_bps informational until Phase C splits)
CREATE TABLE IF NOT EXISTS public.asset_collabs (
  asset_id    uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'featured' CHECK (role IN ('featured','collab','curator')),
  royalty_bps int  NOT NULL DEFAULT 0 CHECK (royalty_bps BETWEEN 0 AND 10000),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, user_id)
);
ALTER TABLE public.asset_collabs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS collab_select ON public.asset_collabs;
DROP POLICY IF EXISTS collab_write_owner ON public.asset_collabs;
CREATE POLICY collab_select ON public.asset_collabs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_collabs.asset_id));
CREATE POLICY collab_write_owner ON public.asset_collabs FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_collabs.asset_id AND d.user_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_collabs.asset_id AND d.user_id = auth.uid()));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.asset_collabs TO authenticated;

-- Rich emoji reactions (one emoji per user per asset)
CREATE TABLE IF NOT EXISTS public.asset_reactions (
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  emoji      text NOT NULL CHECK (char_length(emoji) BETWEEN 1 AND 8),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (asset_id, user_id)
);
CREATE INDEX IF NOT EXISTS asset_reactions_asset_idx ON public.asset_reactions (asset_id);
ALTER TABLE public.asset_reactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS react_select ON public.asset_reactions;
DROP POLICY IF EXISTS react_insert_self ON public.asset_reactions;
DROP POLICY IF EXISTS react_delete_self ON public.asset_reactions;
CREATE POLICY react_select ON public.asset_reactions FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_reactions.asset_id));
CREATE POLICY react_insert_self ON public.asset_reactions FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_reactions.asset_id));
CREATE POLICY react_delete_self ON public.asset_reactions FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
GRANT SELECT, INSERT, DELETE ON public.asset_reactions TO authenticated;

CREATE OR REPLACE FUNCTION public.toggle_asset_reaction(p_asset uuid, p_emoji text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  cur text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  SELECT emoji INTO cur FROM public.asset_reactions
   WHERE asset_id = p_asset AND user_id = uid;
  IF cur IS NOT NULL AND cur = p_emoji THEN
    DELETE FROM public.asset_reactions WHERE asset_id = p_asset AND user_id = uid;
    RETURN NULL;
  END IF;
  INSERT INTO public.asset_reactions (asset_id, user_id, emoji)
  VALUES (p_asset, uid, left(btrim(p_emoji), 8))
  ON CONFLICT (asset_id, user_id) DO UPDATE SET emoji = EXCLUDED.emoji, created_at = now();
  RETURN left(btrim(p_emoji), 8);
END $$;
REVOKE ALL ON FUNCTION public.toggle_asset_reaction(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_asset_reaction(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_reaction_summary(p_assets uuid[])
RETURNS TABLE(asset_id uuid, emoji text, reaction_count int, mine boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT r.asset_id, r.emoji, count(*)::int,
         bool_or(r.user_id = auth.uid()) AS mine
    FROM public.asset_reactions r
   WHERE r.asset_id = ANY(p_assets)
   GROUP BY r.asset_id, r.emoji;
$$;
REVOKE ALL ON FUNCTION public.get_reaction_summary(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_reaction_summary(uuid[]) TO authenticated;

-- Polls
CREATE TABLE IF NOT EXISTS public.asset_polls (
  poll_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  question   text NOT NULL CHECK (char_length(btrim(question)) BETWEEN 1 AND 140),
  options    jsonb NOT NULL, -- ["A","B",...]
  ends_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.asset_poll_votes (
  poll_id    uuid NOT NULL REFERENCES public.asset_polls(poll_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  option_idx int  NOT NULL CHECK (option_idx >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (poll_id, user_id)
);
ALTER TABLE public.asset_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asset_poll_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS poll_select ON public.asset_polls;
DROP POLICY IF EXISTS poll_insert_owner ON public.asset_polls;
DROP POLICY IF EXISTS pv_select ON public.asset_poll_votes;
DROP POLICY IF EXISTS pv_insert_self ON public.asset_poll_votes;
CREATE POLICY poll_select ON public.asset_polls FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = asset_polls.asset_id));
CREATE POLICY poll_insert_owner ON public.asset_polls FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.digital_assets d
     WHERE d.asset_id = asset_polls.asset_id AND d.user_id = auth.uid()));
CREATE POLICY pv_select ON public.asset_poll_votes FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.asset_polls p WHERE p.poll_id = asset_poll_votes.poll_id));
CREATE POLICY pv_insert_self ON public.asset_poll_votes FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT ON public.asset_polls TO authenticated;
GRANT SELECT, INSERT ON public.asset_poll_votes TO authenticated;

-- Live presence (coarse; client throttles writes)
CREATE TABLE IF NOT EXISTS public.explorer_presence (
  user_id    uuid PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
  lat        double precision NOT NULL,
  lon        double precision NOT NULL,
  asset_id   uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  visible    boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.explorer_presence ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS presence_select ON public.explorer_presence;
DROP POLICY IF EXISTS presence_upsert_self ON public.explorer_presence;
CREATE POLICY presence_select ON public.explorer_presence FOR SELECT TO authenticated
  USING (visible = true AND updated_at > now() - interval '15 minutes');
CREATE POLICY presence_upsert_self ON public.explorer_presence FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.explorer_presence TO authenticated;

CREATE OR REPLACE FUNCTION public.upsert_presence(
  p_lat double precision, p_lon double precision, p_asset uuid DEFAULT NULL, p_visible boolean DEFAULT true
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  INSERT INTO public.explorer_presence (user_id, lat, lon, asset_id, visible, updated_at)
  VALUES (auth.uid(), p_lat, p_lon, p_asset, coalesce(p_visible, true), now())
  ON CONFLICT (user_id) DO UPDATE
    SET lat = EXCLUDED.lat, lon = EXCLUDED.lon, asset_id = EXCLUDED.asset_id,
        visible = EXCLUDED.visible, updated_at = now();
END $$;
REVOKE ALL ON FUNCTION public.upsert_presence(double precision, double precision, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_presence(double precision, double precision, uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_nearby_explorers(
  p_lat double precision, p_lon double precision, p_radius_m double precision DEFAULT 200, p_limit int DEFAULT 20
) RETURNS TABLE(user_id uuid, asset_id uuid, updated_at timestamptz, distance_m double precision)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT p.user_id, p.asset_id, p.updated_at,
         (6371000 * acos(least(1::float8, greatest(-1::float8,
            cos(radians(p_lat)) * cos(radians(p.lat)) * cos(radians(p.lon) - radians(p_lon))
            + sin(radians(p_lat)) * sin(radians(p.lat)))))) AS distance_m
    FROM public.explorer_presence p
   WHERE p.visible AND p.updated_at > now() - interval '15 minutes'
     AND p.user_id <> auth.uid()
     AND (6371000 * acos(least(1::float8, greatest(-1::float8,
            cos(radians(p_lat)) * cos(radians(p.lat)) * cos(radians(p.lon) - radians(p_lon))
            + sin(radians(p_lat)) * sin(radians(p.lat)))))) <= greatest(p_radius_m, 50)
   ORDER BY distance_m
   LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
$$;
REVOKE ALL ON FUNCTION public.get_nearby_explorers(double precision, double precision, double precision, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_nearby_explorers(double precision, double precision, double precision, int) TO authenticated;

-- AR events
CREATE TABLE IF NOT EXISTS public.ar_events (
  event_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id     uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  title       text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  detail      text CHECK (detail IS NULL OR char_length(detail) <= 400),
  lat         double precision NOT NULL,
  lon         double precision NOT NULL,
  place_name  text,
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.ar_event_rsvps (
  event_id   uuid NOT NULL REFERENCES public.ar_events(event_id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'going' CHECK (status IN ('going','maybe','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, user_id)
);
ALTER TABLE public.ar_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ar_event_rsvps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ev_select ON public.ar_events;
DROP POLICY IF EXISTS ev_insert_self ON public.ar_events;
DROP POLICY IF EXISTS ev_update_host ON public.ar_events;
DROP POLICY IF EXISTS rsvp_select ON public.ar_event_rsvps;
DROP POLICY IF EXISTS rsvp_write_self ON public.ar_event_rsvps;
CREATE POLICY ev_select ON public.ar_events FOR SELECT TO authenticated USING (true);
CREATE POLICY ev_insert_self ON public.ar_events FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = host_id);
CREATE POLICY ev_update_host ON public.ar_events FOR UPDATE TO authenticated
  USING (auth.uid() = host_id);
CREATE POLICY rsvp_select ON public.ar_event_rsvps FOR SELECT TO authenticated USING (true);
CREATE POLICY rsvp_write_self ON public.ar_event_rsvps FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE ON public.ar_events TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ar_event_rsvps TO authenticated;

-- Close friends + mutes
CREATE TABLE IF NOT EXISTS public.close_friends (
  owner_id   uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  friend_id  uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, friend_id),
  CHECK (owner_id <> friend_id)
);
CREATE TABLE IF NOT EXISTS public.user_mutes (
  muter_id   uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  muted_id   uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (muter_id, muted_id),
  CHECK (muter_id <> muted_id)
);
ALTER TABLE public.close_friends ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_mutes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cf_all_self ON public.close_friends;
DROP POLICY IF EXISTS mute_all_self ON public.user_mutes;
CREATE POLICY cf_all_self ON public.close_friends FOR ALL TO authenticated
  USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY mute_all_self ON public.user_mutes FOR ALL TO authenticated
  USING (auth.uid() = muter_id) WITH CHECK (auth.uid() = muter_id);
GRANT SELECT, INSERT, DELETE ON public.close_friends TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.user_mutes TO authenticated;

-- Comment pin / hide by creator
ALTER TABLE public.asset_comments
  ADD COLUMN IF NOT EXISTS pinned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hidden_by_creator boolean NOT NULL DEFAULT false;

COMMIT;
