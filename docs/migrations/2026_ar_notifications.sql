-- =============================================================================
-- Locolo AR — Notifications: activity inbox, push fan-out, cross-device read state
--
-- Run AFTER 2026_ar_safety_and_hardening.sql and 2026_ar_social.sql (depends on
-- user_blocks, asset_comments and the da_select visibility policy).
-- One transaction, idempotent (safe to re-run).
--
-- What it adds:
--   notifications        one row per event for a recipient; filled by triggers
--   notification_prefs   per-user push switches (the app writes these)
--   device_tokens        APNs tokens, registered through SECURITY DEFINER RPCs
--   conversation_reads   message read state synced across a user's devices
--   app_config           feature flags the client reads (push_enabled)
--
-- Push delivery: a Database Webhook on notifications INSERT calls the
-- send-push edge function (see docs/LOCOLO_AR_STATUS.md §5.3c). Until that is
-- set up (and app_config.push_enabled is true) the app shows the same events
-- as local notifications while it is running, and the Activity screen reads
-- this table either way.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. notifications
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  notification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  actor_id        uuid          REFERENCES public.users(user_id) ON DELETE CASCADE,
  type            text NOT NULL,
  asset_id        uuid REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  comment_id      uuid REFERENCES public.asset_comments(comment_id) ON DELETE CASCADE,
  offer_id        uuid,
  conversation_id text,
  body            text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  read_at         timestamptz
);

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'follow', 'hype', 'comment', 'mention', 'offer', 'offer_status',
  'message', 'new_post', 'discovery', 'milestone'));

CREATE INDEX IF NOT EXISTS notifications_recipient_idx
  ON public.notifications (recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_unread_idx
  ON public.notifications (recipient_id) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS notifications_actor_idx
  ON public.notifications (actor_id, type, created_at DESC);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS notif_select ON public.notifications;
DROP POLICY IF EXISTS notif_update ON public.notifications;
DROP POLICY IF EXISTS notif_delete ON public.notifications;
CREATE POLICY notif_select ON public.notifications FOR SELECT TO authenticated
  USING (auth.uid() = recipient_id);
CREATE POLICY notif_update ON public.notifications FOR UPDATE TO authenticated
  USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
CREATE POLICY notif_delete ON public.notifications FOR DELETE TO authenticated
  USING (auth.uid() = recipient_id);

-- Rows are only ever created by the triggers/RPCs below; clients may only
-- mark them read or clear them.
REVOKE ALL ON public.notifications FROM anon, authenticated;
GRANT SELECT, DELETE ON public.notifications TO authenticated;
GRANT UPDATE (read_at) ON public.notifications TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. notification_prefs (server-side push switches; missing row = all on)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_prefs (
  user_id    uuid PRIMARY KEY REFERENCES public.users(user_id) ON DELETE CASCADE,
  follows    boolean NOT NULL DEFAULT true,
  hypes      boolean NOT NULL DEFAULT true,
  comments   boolean NOT NULL DEFAULT true,
  mentions   boolean NOT NULL DEFAULT true,
  offers     boolean NOT NULL DEFAULT true,
  messages   boolean NOT NULL DEFAULT true,
  new_posts  boolean NOT NULL DEFAULT true,
  milestones boolean NOT NULL DEFAULT true,
  nearby     boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.notification_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS np_all_self ON public.notification_prefs;
CREATE POLICY np_all_self ON public.notification_prefs FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_prefs TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. device_tokens (APNs)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.device_tokens (
  token       text PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  platform    text NOT NULL DEFAULT 'ios',
  environment text NOT NULL DEFAULT 'production' CHECK (environment IN ('sandbox', 'production')),
  bundle_id   text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON public.device_tokens (user_id);
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dt_select_self ON public.device_tokens;
DROP POLICY IF EXISTS dt_delete_self ON public.device_tokens;
CREATE POLICY dt_select_self ON public.device_tokens FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY dt_delete_self ON public.device_tokens FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
REVOKE ALL ON public.device_tokens FROM anon, authenticated;
GRANT SELECT, DELETE ON public.device_tokens TO authenticated;

-- A token belongs to one device; whoever is signed in on it now owns it, so a
-- shared phone never pushes the previous account's notifications.
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token text, p_environment text DEFAULT 'production', p_bundle text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501';
  END IF;
  IF p_token IS NULL OR p_token !~ '^[0-9a-fA-F]{32,200}$' THEN
    RAISE EXCEPTION 'invalid token' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.device_tokens (token, user_id, environment, bundle_id, updated_at)
  VALUES (lower(p_token), auth.uid(),
          CASE WHEN p_environment = 'sandbox' THEN 'sandbox' ELSE 'production' END,
          p_bundle, now())
  ON CONFLICT (token) DO UPDATE
    SET user_id = excluded.user_id, environment = excluded.environment,
        bundle_id = excluded.bundle_id, updated_at = now();
END $$;
REVOKE ALL ON FUNCTION public.register_device_token(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_device_token(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.unregister_device_token(p_token text)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  DELETE FROM public.device_tokens WHERE token = lower(p_token) AND user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.unregister_device_token(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_device_token(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4. app_config — flags the client reads. Flip push_enabled to true once the
--    send-push function and its webhook are live (the app then stops posting
--    its own local fallbacks, so users don't get everything twice).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  key   text PRIMARY KEY,
  value jsonb NOT NULL
);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_config_read ON public.app_config;
CREATE POLICY app_config_read ON public.app_config FOR SELECT TO authenticated USING (true);
REVOKE ALL ON public.app_config FROM anon, authenticated;
GRANT SELECT ON public.app_config TO authenticated;
INSERT INTO public.app_config (key, value) VALUES ('push_enabled', 'false')
  ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 5. _notify — the single insert path. Skips self-notifications, anyone the
--    recipient has blocked, and repeats of follow/hype within 24 h (so a
--    follow/unfollow loop can't spam).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._notify(
  p_recipient uuid, p_actor uuid, p_type text,
  p_asset uuid DEFAULT NULL, p_comment uuid DEFAULT NULL, p_offer uuid DEFAULT NULL,
  p_conversation text DEFAULT NULL, p_body text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_recipient IS NULL OR p_recipient = p_actor THEN RETURN; END IF;
  IF p_actor IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.user_blocks b
        WHERE b.blocker_id = p_recipient AND b.blocked_id = p_actor) THEN
    RETURN;
  END IF;
  IF p_type IN ('follow', 'hype') AND EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = p_recipient AND n.actor_id = p_actor AND n.type = p_type
          AND n.asset_id IS NOT DISTINCT FROM p_asset
          AND n.created_at > now() - interval '24 hours') THEN
    RETURN;
  END IF;
  INSERT INTO public.notifications
    (recipient_id, actor_id, type, asset_id, comment_id, offer_id, conversation_id, body)
  VALUES (p_recipient, p_actor, p_type, p_asset, p_comment, p_offer, p_conversation,
          left(p_body, 280));
END $$;
REVOKE ALL ON FUNCTION public._notify(uuid, uuid, text, uuid, uuid, uuid, text, text)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Follows → "X started following you"
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_follow()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.notifications
     WHERE recipient_id = OLD.followee_id AND actor_id = OLD.follower_id
       AND type = 'follow' AND read_at IS NULL;
    RETURN OLD;
  END IF;
  IF coalesce(NEW.status, 'accepted') <> 'accepted' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND coalesce(OLD.status, 'accepted') = 'accepted' THEN RETURN NEW; END IF;
  PERFORM public._notify(NEW.followee_id, NEW.follower_id, 'follow');
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_follow() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS follows_notify ON public.follows;
CREATE TRIGGER follows_notify
  AFTER INSERT OR UPDATE OF status OR DELETE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();

-- ---------------------------------------------------------------------------
-- 7. Hypes → "X hyped <asset>" (un-hype removes the unread notification)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_hype()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE owner uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.notifications
     WHERE actor_id = OLD.user_id AND asset_id = OLD.asset_id
       AND type = 'hype' AND read_at IS NULL;
    RETURN OLD;
  END IF;
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  PERFORM public._notify(owner, NEW.user_id, 'hype', NEW.asset_id);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_hype() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS asset_hype_notify ON public.asset_hype;
CREATE TRIGGER asset_hype_notify
  AFTER INSERT OR DELETE ON public.asset_hype
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_hype();

-- ---------------------------------------------------------------------------
-- 8. Comments → owner gets "commented"; each @handle gets "mentioned you"
--    (only people who can see the asset; deleting the comment cascades).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_comment()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner uuid;
  vis   text;
  handle text;
  mentioned uuid;
  sent  int := 0;
BEGIN
  SELECT user_id, coalesce(visibility, 'public') INTO owner, vis
    FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  PERFORM public._notify(owner, NEW.user_id, 'comment', NEW.asset_id, NEW.comment_id,
                         NULL, NULL, NEW.body);

  FOR handle IN
    SELECT DISTINCT lower(m[1])
      FROM regexp_matches(NEW.body, '@([A-Za-z0-9_.]{2,30})', 'g') AS m
  LOOP
    EXIT WHEN sent >= 5;
    SELECT u.user_id INTO mentioned FROM public.users u WHERE lower(u.username) = handle;
    CONTINUE WHEN mentioned IS NULL OR mentioned = owner OR mentioned = NEW.user_id;
    CONTINUE WHEN vis = 'private';
    CONTINUE WHEN vis = 'friends' AND NOT EXISTS (
      SELECT 1 FROM public.follows f
       WHERE f.follower_id = mentioned AND f.followee_id = owner AND f.status = 'accepted');
    PERFORM public._notify(mentioned, NEW.user_id, 'mention', NEW.asset_id, NEW.comment_id,
                           NULL, NULL, NEW.body);
    sent := sent + 1;
  END LOOP;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_comment() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS asset_comments_notify ON public.asset_comments;
CREATE TRIGGER asset_comments_notify
  AFTER INSERT ON public.asset_comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_comment();

-- ---------------------------------------------------------------------------
-- 9. Offers → owner gets "offered $X"; buyer hears when it's accepted/declined
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_offer()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF TG_OP = 'INSERT' THEN
    PERFORM public._notify(owner, NEW.buyer_id, 'offer', NEW.asset_id, NULL, NEW.offer_id,
                           NULL, NEW.amount::text);
  ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status IN ('accepted', 'rejected') THEN
    PERFORM public._notify(NEW.buyer_id, owner, 'offer_status', NEW.asset_id, NULL, NEW.offer_id,
                           NULL, NEW.status || ':' || NEW.amount::text);
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_offer() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS offers_notify ON public.offers;
CREATE TRIGGER offers_notify
  AFTER INSERT OR UPDATE OF status ON public.offers
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_offer();

-- ---------------------------------------------------------------------------
-- 10. New creation → followers get "X dropped <asset>" (public & friends only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_new_asset()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF coalesce(NEW.visibility, 'public') = 'private' THEN RETURN NEW; END IF;
  INSERT INTO public.notifications (recipient_id, actor_id, type, asset_id, body)
  SELECT f.follower_id, NEW.user_id, 'new_post', NEW.asset_id, NEW.name
    FROM public.follows f
   WHERE f.followee_id = NEW.user_id AND f.status = 'accepted'
     AND f.follower_id <> NEW.user_id
     AND NOT EXISTS (SELECT 1 FROM public.user_blocks b
                      WHERE b.blocker_id = f.follower_id AND b.blocked_id = NEW.user_id)
   LIMIT 5000;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_new_asset() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS digital_assets_notify_new ON public.digital_assets;
CREATE TRIGGER digital_assets_notify_new
  AFTER INSERT ON public.digital_assets
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_new_asset();

-- ---------------------------------------------------------------------------
-- 11. Discoveries → "X discovered <asset> in AR" (a new unique explorer).
--     At most one unread discovery per asset per hour so busy spots batch up.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_discovery()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF owner IS NULL OR owner = NEW.user_id THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM public.notifications n
              WHERE n.recipient_id = owner AND n.asset_id = NEW.asset_id
                AND n.type = 'discovery' AND n.read_at IS NULL
                AND n.created_at > now() - interval '1 hour') THEN
    RETURN NEW;
  END IF;
  PERFORM public._notify(owner, NEW.user_id, 'discovery', NEW.asset_id);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_discovery() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS asset_views_notify ON public.asset_views;
CREATE TRIGGER asset_views_notify
  AFTER INSERT ON public.asset_views
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_discovery();

-- ---------------------------------------------------------------------------
-- 12. Milestones → "<asset> just hit 100 hypes" / "50 explorers found <asset>"
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_milestone()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  marks int[] := ARRAY[10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 100000];
  m int;
  hit int;
BEGIN
  hit := NULL;
  FOREACH m IN ARRAY marks LOOP
    IF coalesce(OLD.hype_count, 0) < m AND coalesce(NEW.hype_count, 0) >= m THEN hit := m; END IF;
  END LOOP;
  IF hit IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = NEW.user_id AND n.asset_id = NEW.asset_id
          AND n.type = 'milestone' AND n.body = 'hypes:' || hit) THEN
    PERFORM public._notify(NEW.user_id, NULL, 'milestone', NEW.asset_id, NULL, NULL, NULL,
                           'hypes:' || hit);
  END IF;

  hit := NULL;
  FOREACH m IN ARRAY marks LOOP
    IF coalesce(OLD.view_count, 0) < m AND coalesce(NEW.view_count, 0) >= m THEN hit := m; END IF;
  END LOOP;
  IF hit IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
        WHERE n.recipient_id = NEW.user_id AND n.asset_id = NEW.asset_id
          AND n.type = 'milestone' AND n.body = 'views:' || hit) THEN
    PERFORM public._notify(NEW.user_id, NULL, 'milestone', NEW.asset_id, NULL, NULL, NULL,
                           'views:' || hit);
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.notify_on_milestone() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS digital_assets_notify_milestone ON public.digital_assets;
CREATE TRIGGER digital_assets_notify_milestone
  AFTER UPDATE OF hype_count, view_count ON public.digital_assets
  FOR EACH ROW
  WHEN (NEW.hype_count IS DISTINCT FROM OLD.hype_count OR NEW.view_count IS DISTINCT FROM OLD.view_count)
  EXECUTE FUNCTION public.notify_on_milestone();

-- ---------------------------------------------------------------------------
-- 13. Messages. Chat lives in Firestore, so the sender's app calls this after
--     a successful send. The body is never sent (messages are end-to-end
--     encrypted); push shows "New message from X". Rate-limited per sender,
--     and one unread message notification per conversation is kept fresh
--     instead of stacking.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_message(p_recipient uuid, p_conversation_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE me uuid := auth.uid();
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'sign in required' USING ERRCODE = '42501'; END IF;
  IF p_recipient IS NULL OR p_recipient = me OR coalesce(p_conversation_id, '') = '' THEN RETURN; END IF;
  IF (SELECT count(*) FROM public.notifications
       WHERE actor_id = me AND type = 'message'
         AND created_at > now() - interval '10 minutes') >= 60 THEN
    RETURN;
  END IF;
  DELETE FROM public.notifications
   WHERE recipient_id = p_recipient AND actor_id = me AND type = 'message'
     AND conversation_id = p_conversation_id AND read_at IS NULL;
  PERFORM public._notify(p_recipient, me, 'message', NULL, NULL, NULL, p_conversation_id);
END $$;
REVOKE ALL ON FUNCTION public.notify_message(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notify_message(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 14. conversation_reads — per-user (not per-device) chat read state.
--     Reading a thread on one device clears its unread badge everywhere and
--     marks that conversation's message notifications read.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.conversation_reads (
  user_id         uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  conversation_id text NOT NULL,
  last_read_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);
ALTER TABLE public.conversation_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cr_all_self ON public.conversation_reads;
CREATE POLICY cr_all_self ON public.conversation_reads FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.conversation_reads TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_message_notifications_read()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.notifications
     SET read_at = now()
   WHERE recipient_id = NEW.user_id AND type = 'message'
     AND conversation_id = NEW.conversation_id AND read_at IS NULL
     AND created_at <= NEW.last_read_at + interval '5 seconds';
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.mark_message_notifications_read() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS conversation_reads_mark ON public.conversation_reads;
CREATE TRIGGER conversation_reads_mark
  AFTER INSERT OR UPDATE ON public.conversation_reads
  FOR EACH ROW EXECUTE FUNCTION public.mark_message_notifications_read();

-- ---------------------------------------------------------------------------
-- 15. Housekeeping: keep 90 days of read notifications (run from pg_cron or
--     by hand — nothing depends on it).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_notifications()
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH gone AS (
    DELETE FROM public.notifications
     WHERE read_at IS NOT NULL AND created_at < now() - interval '90 days'
    RETURNING 1)
  SELECT count(*)::int FROM gone;
$$;
REVOKE ALL ON FUNCTION public.prune_notifications() FROM PUBLIC, anon, authenticated;

COMMIT;

-- =============================================================================
-- Verify (as a signed-in user in the SQL editor, or via the app):
--   select * from public.notifications order by created_at desc limit 20;
--   select public.notify_message('<peer uuid>', 'test-convo');  -- then check peer's rows
--   select * from public.app_config;                             -- push_enabled = false
-- After send-push + webhook are live:
--   update public.app_config set value = 'true' where key = 'push_enabled';
-- Optional nightly prune (pg_cron):
--   select cron.schedule('prune-notifications', '17 3 * * *', 'select public.prune_notifications()');
-- =============================================================================
