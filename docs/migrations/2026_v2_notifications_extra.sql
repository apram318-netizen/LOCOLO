-- =============================================================================
-- LOCOLO V2 — Extra notification types for social + marketplace
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.22).
-- Apply after 2026_ar_notifications.sql and §5.20 social tier23.
-- =============================================================================

BEGIN;

ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'follow', 'hype', 'comment', 'mention', 'offer', 'offer_status',
  'message', 'new_post', 'discovery', 'milestone',
  'repost', 'collect', 'reaction', 'comment_reply', 'comment_like',
  'remix', 'tag', 'quest_complete', 'level_up', 'event_reminder',
  'sale', 'royalty', 'outbid', 'story_view'
));

ALTER TABLE public.notification_prefs
  ADD COLUMN IF NOT EXISTS reposts boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS reactions boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS quests boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sales boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS events boolean NOT NULL DEFAULT true;

-- Repost → notify asset owner
CREATE OR REPLACE FUNCTION public.notify_on_repost()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF owner IS NULL OR owner = NEW.user_id THEN RETURN NEW; END IF;
  PERFORM public._notify(owner, NEW.user_id, 'repost', NEW.asset_id, NULL, NULL, NULL, NULL);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS reposts_notify ON public.reposts;
CREATE TRIGGER reposts_notify AFTER INSERT ON public.reposts
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_repost();

-- Reaction → notify owner
CREATE OR REPLACE FUNCTION public.notify_on_reaction()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF owner IS NULL OR owner = NEW.user_id THEN RETURN NEW; END IF;
  PERFORM public._notify(owner, NEW.user_id, 'reaction', NEW.asset_id, NULL, NULL, NULL, NEW.emoji);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS reactions_notify ON public.asset_reactions;
CREATE TRIGGER reactions_notify AFTER INSERT ON public.asset_reactions
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_reaction();

-- Remix → notify parent owner
CREATE OR REPLACE FUNCTION public.notify_on_remix()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  parent_owner uuid;
  remixer uuid;
BEGIN
  SELECT user_id INTO parent_owner FROM public.digital_assets WHERE asset_id = NEW.parent_asset_id;
  SELECT user_id INTO remixer FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF parent_owner IS NULL OR parent_owner = remixer THEN RETURN NEW; END IF;
  PERFORM public._notify(parent_owner, remixer, 'remix', NEW.asset_id, NULL, NULL, NULL, NULL);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS remixes_notify ON public.asset_remixes;
CREATE TRIGGER remixes_notify AFTER INSERT ON public.asset_remixes
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_remix();

-- Board collect → notify asset owner
CREATE OR REPLACE FUNCTION public.notify_on_collect()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.digital_assets WHERE asset_id = NEW.asset_id;
  IF owner IS NULL OR owner = NEW.added_by THEN RETURN NEW; END IF;
  PERFORM public._notify(owner, NEW.added_by, 'collect', NEW.asset_id, NULL, NULL, NULL, NULL);
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS board_items_notify ON public.board_items;
CREATE TRIGGER board_items_notify AFTER INSERT ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_collect();

COMMIT;
