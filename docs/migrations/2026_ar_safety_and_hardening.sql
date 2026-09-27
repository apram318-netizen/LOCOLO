-- =============================================================================
-- Locolo AR — Safety & security hardening
--
-- SUPERSEDES docs/migrations/2026_ar_release_rls.sql (never applied). Run this
-- instead, in the Supabase SQL editor, as one transaction. Idempotent: every
-- policy is dropped-if-exists before being created, so re-running is safe.
--
-- Verified against prod (read-only anon probes, 2026-09-27):
--   * RLS is OFF on public.users → the anon key can read every user's EMAIL.
--   * toggle_asset_hype(p_user, p_asset) trusts p_user → anyone can hype (or
--     un-hype) as anyone.
--   * public.run_sql exists and is callable by API roles.
--   * user_blocks, content_reports, delete_my_account, email_registered do
--     not exist yet (the app already tolerates their absence).
--   * All 10 digital_assets rows have category 'ar_model' (legacy value).
--   * event_attendance (not event_attendees) is the real table name.
--
-- The app build that ships with this migration already:
--   * selects explicit, email-free column lists from users (User.publicColumns)
--   * updates users with returning=minimal and only editable columns
--   * checks "is this email registered?" via email_registered() pre-sign-in
--   * sends signUp username metadata for handle_new_user and tolerates the
--     RLS refusal of the pre-confirmation client insert
--   ⚠️ Apply AFTER that build is live (older builds `select *` on users and
--      will fail to load profiles once the email column is revoked).
--
-- Not covered here (needs prod source we can't read with the anon key):
--   * get_asset_full exists in prod but isn't in the repo — dump it with
--     `select pg_get_functiondef('public.get_asset_full'::regproc);` and commit.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Lock down dangerous helpers
-- ---------------------------------------------------------------------------
DO $$
DECLARE fn regprocedure;
BEGIN
  FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname IN ('run_sql', 'exec_sql')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 2. users — private email, owner-only writes, no forged stats/verification
-- ---------------------------------------------------------------------------
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select      ON public.users;
DROP POLICY IF EXISTS users_insert_self ON public.users;
DROP POLICY IF EXISTS users_update_self ON public.users;
CREATE POLICY users_select      ON public.users FOR SELECT TO authenticated USING (true);
CREATE POLICY users_insert_self ON public.users FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_self ON public.users FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Column privileges: every column except email is readable by signed-in
-- users; anon reads nothing. Built dynamically so new columns aren't missed.
DO $$
DECLARE readable text;
BEGIN
  SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO readable
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'users' AND column_name <> 'email';

  EXECUTE 'REVOKE SELECT, INSERT, UPDATE ON public.users FROM anon, authenticated';
  EXECUTE format('GRANT SELECT (%s) ON public.users TO authenticated', readable);
END $$;

GRANT INSERT (user_id, username, email, name, bio, avatar_url, cover_url, joined_at, stats)
  ON public.users TO authenticated;
GRANT UPDATE (username, name, bio, avatar_url, cover_url, x25519_public_key, key_updated_at)
  ON public.users TO authenticated;

-- Pre-sign-in "does this account exist?" (forgot-password flow). Boolean
-- only — no row data leaves the database.
CREATE OR REPLACE FUNCTION public.email_registered(p_email text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.users WHERE email = lower(trim(p_email)));
$$;
REVOKE ALL ON FUNCTION public.email_registered(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_registered(text) TO anon, authenticated;

-- Profile row on sign-up, created server-side (fixes the "no session until
-- email is confirmed → RLS rejects the client insert" caveat).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  base text := coalesce(nullif(trim(NEW.raw_user_meta_data->>'username'), ''),
                        split_part(NEW.email, '@', 1));
BEGIN
  BEGIN
    INSERT INTO public.users (user_id, username, email, joined_at, stats)
    VALUES (NEW.id, base, lower(NEW.email), now(),
            '{"followers":0,"following":0,"posts":0}'::jsonb)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN unique_violation THEN
    -- username taken: keep the sign-up working with a suffixed handle
    INSERT INTO public.users (user_id, username, email, joined_at, stats)
    VALUES (NEW.id, base || '_' || substr(md5(NEW.id::text), 1, 5), lower(NEW.email), now(),
            '{"followers":0,"following":0,"posts":0}'::jsonb)
    ON CONFLICT (user_id) DO NOTHING;
  END;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 3. AR-core tables
-- ---------------------------------------------------------------------------
ALTER TABLE public.digital_assets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS da_select       ON public.digital_assets;
DROP POLICY IF EXISTS da_insert_owner ON public.digital_assets;
DROP POLICY IF EXISTS da_update_owner ON public.digital_assets;
DROP POLICY IF EXISTS da_delete_owner ON public.digital_assets;
-- Visibility: creation writes public / friends / private; legacy rows carry
-- 'normal' (old rarity value) and are treated as public. SECURITY DEFINER RPCs
-- (e.g. get_nearby_assets) bypass RLS and must apply the same predicate.
CREATE POLICY da_select ON public.digital_assets FOR SELECT TO authenticated USING (
  user_id = auth.uid()
  OR coalesce(visibility, 'public') IN ('public', 'normal')
  OR (visibility = 'friends' AND EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = auth.uid()
          AND f.followee_id = digital_assets.user_id
          AND f.status = 'accepted'))
);
CREATE POLICY da_insert_owner ON public.digital_assets FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY da_update_owner ON public.digital_assets FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY da_delete_owner ON public.digital_assets FOR DELETE TO authenticated USING (auth.uid() = user_id);

ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS loc_select ON public.locations;
DROP POLICY IF EXISTS loc_insert ON public.locations;
CREATE POLICY loc_select ON public.locations FOR SELECT TO authenticated USING (true);
CREATE POLICY loc_insert ON public.locations FOR INSERT TO authenticated WITH CHECK (true);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS follows_select      ON public.follows;
DROP POLICY IF EXISTS follows_insert_self ON public.follows;
DROP POLICY IF EXISTS follows_update_self ON public.follows;
DROP POLICY IF EXISTS follows_delete_self ON public.follows;
CREATE POLICY follows_select      ON public.follows FOR SELECT TO authenticated USING (true);
CREATE POLICY follows_insert_self ON public.follows FOR INSERT TO authenticated WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_update_self ON public.follows FOR UPDATE TO authenticated
  USING (auth.uid() = follower_id) WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_delete_self ON public.follows FOR DELETE TO authenticated USING (auth.uid() = follower_id);

-- offers: buyers create/withdraw their own; the ASSET OWNER accepts/rejects.
-- (The old draft had no seller policy, so "Accept" could never work.)
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS offers_select        ON public.offers;
DROP POLICY IF EXISTS offers_insert_buyer  ON public.offers;
DROP POLICY IF EXISTS offers_update_buyer  ON public.offers;
DROP POLICY IF EXISTS offers_update_seller ON public.offers;
DROP POLICY IF EXISTS offers_delete_buyer  ON public.offers;
-- Readable by any signed-in user: highest_offer_for_asset (possibly SECURITY
-- INVOKER) must see every bid to show the current top offer.
CREATE POLICY offers_select ON public.offers FOR SELECT TO authenticated USING (true);
CREATE POLICY offers_insert_buyer ON public.offers FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = buyer_id AND status = 'pending');
CREATE POLICY offers_update_buyer ON public.offers FOR UPDATE TO authenticated
  USING (auth.uid() = buyer_id) WITH CHECK (auth.uid() = buyer_id AND status IN ('pending', 'withdrawn'));
CREATE POLICY offers_update_seller ON public.offers FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = offers.asset_id AND d.user_id = auth.uid()))
  WITH CHECK (status IN ('pending', 'accepted', 'rejected'));
CREATE POLICY offers_delete_buyer ON public.offers FOR DELETE TO authenticated USING (auth.uid() = buyer_id);

ALTER TABLE public.asset_views ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS av_all_self ON public.asset_views;
CREATE POLICY av_all_self ON public.asset_views FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.asset_hype ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ah_select      ON public.asset_hype;
DROP POLICY IF EXISTS ah_insert_self ON public.asset_hype;
DROP POLICY IF EXISTS ah_delete_self ON public.asset_hype;
CREATE POLICY ah_select      ON public.asset_hype FOR SELECT TO authenticated USING (true);
CREATE POLICY ah_insert_self ON public.asset_hype FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY ah_delete_self ON public.asset_hype FOR DELETE TO authenticated USING (auth.uid() = user_id);

ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS wl_all_self ON public.wishlist;
CREATE POLICY wl_all_self ON public.wishlist FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ph_select ON public.price_history;
CREATE POLICY ph_select ON public.price_history FOR SELECT TO authenticated USING (true);

-- ---------------------------------------------------------------------------
-- 4. toggle_asset_hype — the caller can only hype as themselves
-- ---------------------------------------------------------------------------
-- Drop every existing overload first (prod's parameter types are unknown and
-- a uuid/text pair of overloads would make PostgREST calls ambiguous).
DO $$
DECLARE fn regprocedure;
BEGIN
  FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'toggle_asset_hype'
  LOOP
    EXECUTE format('DROP FUNCTION %s', fn);
  END LOOP;
END $$;

CREATE FUNCTION public.toggle_asset_hype(p_user uuid, p_asset uuid)
RETURNS TABLE(hyped boolean, hype_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  now_hyped boolean;
  total integer;
BEGIN
  IF auth.uid() IS NULL OR p_user IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'can only hype as yourself' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.asset_hype WHERE user_id = p_user AND asset_id = p_asset;
  IF FOUND THEN
    now_hyped := false;
  ELSE
    INSERT INTO public.asset_hype (user_id, asset_id) VALUES (p_user, p_asset);
    now_hyped := true;
  END IF;

  -- Recount rather than +/-1 so this stays correct alongside any legacy
  -- counter trigger and self-heals drift.
  SELECT count(*)::int INTO total FROM public.asset_hype WHERE asset_id = p_asset;
  UPDATE public.digital_assets SET hype_count = total WHERE asset_id = p_asset;

  RETURN QUERY SELECT now_hyped, total;
END $$;
REVOKE ALL ON FUNCTION public.toggle_asset_hype(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.toggle_asset_hype(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4b. view_count = unique explorers (asset placed in someone's AR session)
-- ---------------------------------------------------------------------------
-- The client upserts asset_views on (user_id, asset_id), so AFTER INSERT fires
-- once per new viewer; repeat sightings are UPDATEs and don't count. Owners
-- viewing their own asset don't count. SECURITY DEFINER because viewers can't
-- update other people's digital_assets rows.
CREATE OR REPLACE FUNCTION public.bump_asset_view_count()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.digital_assets
     SET view_count = coalesce(view_count, 0) + 1
   WHERE asset_id = NEW.asset_id
     AND user_id IS DISTINCT FROM NEW.user_id;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.bump_asset_view_count() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS asset_views_bump_count ON public.asset_views;
CREATE TRIGGER asset_views_bump_count
  AFTER INSERT ON public.asset_views
  FOR EACH ROW EXECUTE FUNCTION public.bump_asset_view_count();

-- One-off backfill from existing view records.
UPDATE public.digital_assets d
   SET view_count = sub.n
  FROM (SELECT v.asset_id, count(*)::int AS n
          FROM public.asset_views v
          JOIN public.digital_assets a ON a.asset_id = v.asset_id
         WHERE v.user_id IS DISTINCT FROM a.user_id
         GROUP BY v.asset_id) sub
 WHERE d.asset_id = sub.asset_id;

-- ---------------------------------------------------------------------------
-- 4c. Read RPCs must respect da_select (private / friends visibility)
-- ---------------------------------------------------------------------------
-- get_recommended_assets and get_asset_full exist only in prod, so their
-- security mode is unknown here. SECURITY DEFINER would bypass RLS and leak
-- private assets; force invoker mode. They only need digital_assets,
-- locations and users.taste_embedding, all readable by `authenticated`.
-- Smoke-test Explore + a deep link after applying.
DO $$
DECLARE fn regprocedure;
BEGIN
  FOR fn IN SELECT p.oid::regprocedure FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('get_nearby_assets_full', 'get_recommended_assets', 'get_asset_full')
              AND p.prosecdef
  LOOP
    EXECUTE format('ALTER FUNCTION %s SECURITY INVOKER', fn);
    RAISE NOTICE 'Switched % to SECURITY INVOKER', fn;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 5. Trust & safety: blocks + reports (App Store guideline 1.2)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_blocks (
  blocker_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ub_all_self ON public.user_blocks;
CREATE POLICY ub_all_self ON public.user_blocks FOR ALL TO authenticated
  USING (auth.uid() = blocker_id) WITH CHECK (auth.uid() = blocker_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_blocks TO authenticated;

CREATE TABLE IF NOT EXISTS public.content_reports (
  report_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id      uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  asset_id         uuid REFERENCES public.digital_assets(asset_id) ON DELETE SET NULL,
  reported_user_id uuid REFERENCES public.users(user_id) ON DELETE SET NULL,
  reason           text NOT NULL CHECK (reason IN ('spam','harassment','nudity','violence','hate',
                                                   'intellectual_property','unsafe_location','other')),
  details          text CHECK (char_length(details) <= 1000),
  status           text NOT NULL DEFAULT 'open' CHECK (status IN ('open','actioned','dismissed')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  reviewed_at      timestamptz,
  CHECK (asset_id IS NOT NULL OR reported_user_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS content_reports_open_idx ON public.content_reports (created_at) WHERE status = 'open';
ALTER TABLE public.content_reports ENABLE ROW LEVEL SECURITY;
-- Reporters can file; only the service role / dashboard reads the queue.
DROP POLICY IF EXISTS cr_insert_self ON public.content_reports;
CREATE POLICY cr_insert_self ON public.content_reports FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = reporter_id);
GRANT INSERT ON public.content_reports TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. Self-serve account deletion (App Store guideline 5.1.1(v))
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not signed in' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_blocks     WHERE blocker_id = uid OR blocked_id = uid;
  DELETE FROM public.content_reports WHERE reporter_id = uid;
  DELETE FROM public.asset_hype      WHERE user_id = uid;
  DELETE FROM public.asset_views     WHERE user_id = uid;
  DELETE FROM public.wishlist        WHERE user_id = uid;
  DELETE FROM public.offers          WHERE buyer_id = uid
     OR asset_id IN (SELECT asset_id FROM public.digital_assets WHERE user_id = uid);
  DELETE FROM public.follows         WHERE follower_id = uid OR followee_id = uid;
  DELETE FROM public.digital_assets  WHERE user_id = uid;
  DELETE FROM public.users           WHERE user_id = uid;
  DELETE FROM auth.users             WHERE id = uid;
  -- Storage objects (uploaded USDZ / thumbnails) are left for a scheduled
  -- cleanup job; they're unreachable once the asset rows are gone.
END $$;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. Legacy / non-AR tables: authenticated-only baseline (no anon access)
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'posts','listings','orders','payments','loops','categories','places',
    'events','activities','hypes','echoes','real_memories','loop_time_counters',
    'visits','event_attendance'
  ] LOOP
    CONTINUE WHEN to_regclass('public.' || t) IS NULL;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_sel', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_ins', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_upd', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_del', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (true)', t || '_sel', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (true)', t || '_ins', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (true) WITH CHECK (true)', t || '_upd', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (true)', t || '_del', t);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 8. Data fixes
-- ---------------------------------------------------------------------------
-- Legacy creation wrote 'ar_model'; the app's category taxonomy uses '3d'.
-- (The client also normalises this, so the UPDATE is cosmetic but tidy.)
UPDATE public.digital_assets SET category = '3d' WHERE category IN ('ar_model', 'model', 'usdz');

COMMIT;

-- =============================================================================
-- Verify (run after COMMIT):
--   -- as anon (REST, anon key): must now fail / return nothing
--   GET /rest/v1/users?select=email            → 401/permission denied
--   -- as a signed-in user:
--   GET /rest/v1/users?select=user_id,username → rows
--   GET /rest/v1/users?select=email            → permission denied for column email
--   POST /rest/v1/rpc/toggle_asset_hype {p_user:<someone else>} → 42501
--
-- Rollback (emergency only):
--   ALTER TABLE public.<t> DISABLE ROW LEVEL SECURITY;
--   GRANT SELECT, INSERT, UPDATE ON public.users TO anon, authenticated;
--   DROP TRIGGER on_auth_user_created ON auth.users;
-- =============================================================================
