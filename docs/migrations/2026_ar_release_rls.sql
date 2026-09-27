-- =============================================================================
-- ⛔ SUPERSEDED — DO NOT APPLY. Use 2026_ar_safety_and_hardening.sql instead.
--    This draft left users.email readable, had no seller policy on offers,
--    trusted toggle_asset_hype's p_user, and wasn't idempotent.
-- =============================================================================
-- Locolo AR Release — Row Level Security (WS9 security hardening)
--
-- ⚠️ DO NOT APPLY BLINDLY. Review + confirm the caveat below first, then run in
-- the Supabase SQL editor. This is intentionally NOT auto-applied because it can
-- break sign-up if email confirmation changes the auth timing (see CAVEAT).
--
-- CONTEXT (verified 2026-09-27):
--   * The app authenticates with Supabase Auth, so auth.uid() is populated for
--     signed-in requests.
--   * signUp() inserts public.users with id = auth user id, so
--     users.user_id == auth.uid(). Owner-based policies below are therefore
--     correct.
--
-- 🔴 CAVEAT — sign-up insert timing:
--   UsersViewModel.signUp() inserts the public.users row immediately after
--   auth.signUp(). If "Confirm email" is ENABLED in Supabase Auth settings,
--   signUp() does NOT return an active session, so auth.uid() is NULL at that
--   moment and the users INSERT policy (auth.uid() = user_id) will REJECT it,
--   breaking registration. Choose one before applying:
--     (a) Disable email confirmation (Auth → Providers → Email), OR
--     (b) Move the public.users insert to AFTER OTP verification (session live), OR
--     (c) Replace the client insert with a SECURITY DEFINER trigger on
--         auth.users (standard Supabase handle_new_user pattern).
--
-- Model: v1 is AR-only. AR-core tables get proper public-read + owner-write
-- policies. Legacy/non-AR tables get a baseline (authenticated-only, no anon)
-- so the critical "anon can read/write everything" advisory is resolved; tighten
-- them when those features return.
-- =============================================================================

-- ---------- AR-CORE TABLES ----------

-- users: anyone signed in can read profiles; you may only write your own row.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_select ON public.users FOR SELECT TO authenticated USING (true);
CREATE POLICY users_insert_self ON public.users FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY users_update_self ON public.users FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- digital_assets: public read; owner-only writes.
ALTER TABLE public.digital_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY da_select ON public.digital_assets FOR SELECT TO authenticated USING (true);
CREATE POLICY da_insert_owner ON public.digital_assets FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY da_update_owner ON public.digital_assets FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY da_delete_owner ON public.digital_assets FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- locations: shared reference rows (no owner column). Read + create by any user.
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;
CREATE POLICY loc_select ON public.locations FOR SELECT TO authenticated USING (true);
CREATE POLICY loc_insert ON public.locations FOR INSERT TO authenticated WITH CHECK (true);

-- follows: public read; you may only create/remove your own follow edges.
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY follows_select ON public.follows FOR SELECT TO authenticated USING (true);
CREATE POLICY follows_insert_self ON public.follows FOR INSERT TO authenticated WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_update_self ON public.follows FOR UPDATE TO authenticated USING (auth.uid() = follower_id) WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_delete_self ON public.follows FOR DELETE TO authenticated USING (auth.uid() = follower_id);

-- offers: read by any signed-in user; created/managed by the buyer.
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
CREATE POLICY offers_select ON public.offers FOR SELECT TO authenticated USING (true);
CREATE POLICY offers_insert_buyer ON public.offers FOR INSERT TO authenticated WITH CHECK (auth.uid() = buyer_id);
CREATE POLICY offers_update_buyer ON public.offers FOR UPDATE TO authenticated USING (auth.uid() = buyer_id) WITH CHECK (auth.uid() = buyer_id);
CREATE POLICY offers_delete_buyer ON public.offers FOR DELETE TO authenticated USING (auth.uid() = buyer_id);

-- asset_views: your own view records only.
ALTER TABLE public.asset_views ENABLE ROW LEVEL SECURITY;
CREATE POLICY av_all_self ON public.asset_views FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- asset_hype: public read (for counts); you may only add/remove your own hype.
ALTER TABLE public.asset_hype ENABLE ROW LEVEL SECURITY;
CREATE POLICY ah_select ON public.asset_hype FOR SELECT TO authenticated USING (true);
CREATE POLICY ah_insert_self ON public.asset_hype FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY ah_delete_self ON public.asset_hype FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- wishlist: private to the owner.
ALTER TABLE public.wishlist ENABLE ROW LEVEL SECURITY;
CREATE POLICY wl_all_self ON public.wishlist FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- price_history: read-only to clients; writes via service role only (no write policy).
ALTER TABLE public.price_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY ph_select ON public.price_history FOR SELECT TO authenticated USING (true);

-- ---------- LEGACY / NON-AR TABLES (baseline: authenticated-only) ----------
-- Not used by AR v1. This removes anon read/write (the critical advisory) while
-- deferring precise ownership modeling until these features return.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'posts','listings','orders','payments','loops','categories','places',
    'events','activities','hypes','echoes','real_memories','loop_time_counters',
    'visits','event_attendance'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (true);', t||'_sel', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (true);', t||'_ins', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (true) WITH CHECK (true);', t||'_upd', t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (true);', t||'_del', t);
  END LOOP;
END $$;

-- =============================================================================
-- Rollback: ALTER TABLE public.<t> DISABLE ROW LEVEL SECURITY; DROP POLICY ...;
-- =============================================================================
