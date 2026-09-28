-- =============================================================================
-- LOCOLO V2 — Pending storage deletes for account cleanup (§5.9 / §5.27)
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.27).
-- delete_my_account removes DB rows but not Storage objects. This migration
-- adds pending_storage_deletes + enqueue_storage_cleanup, then redefines
-- delete_my_account to enqueue paths BEFORE row deletes. Edge cron:
-- supabase/functions/purge-storage. Idempotent.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.pending_storage_deletes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL,
  bucket      text NOT NULL,
  object_path text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  purged_at   timestamptz
);
CREATE INDEX IF NOT EXISTS pending_storage_deletes_open_idx
  ON public.pending_storage_deletes (created_at)
  WHERE purged_at IS NULL;

ALTER TABLE public.pending_storage_deletes ENABLE ROW LEVEL SECURITY;
-- Service role only (edge job). No client policies.
REVOKE ALL ON public.pending_storage_deletes FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.pending_storage_deletes TO service_role;

-- Call from delete_my_account to enqueue known path prefixes.
CREATE OR REPLACE FUNCTION public.enqueue_storage_cleanup(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.pending_storage_deletes (user_id, bucket, object_path)
  VALUES
    (p_user, 'media', 'stories/' || lower(p_user::text) || '/'),
    (p_user, 'media', 'avatars/' || lower(p_user::text) || '.jpg'),
    (p_user, 'media', 'covers/' || lower(p_user::text) || '.jpg');

  INSERT INTO public.pending_storage_deletes (user_id, bucket, object_path)
  SELECT p_user, 'digital_assets', 'prefix:DigitalArt:' || da.asset_id::text
    FROM public.digital_assets da WHERE da.user_id = p_user;
END $$;
-- Callable from delete_my_account (SECURITY DEFINER) and service_role cron.
REVOKE ALL ON FUNCTION public.enqueue_storage_cleanup(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_storage_cleanup(uuid) TO service_role;

COMMENT ON FUNCTION public.enqueue_storage_cleanup(uuid) IS
  'Enqueue storage prefixes for user. Called by delete_my_account; purge via edge cron.';

-- Redefine delete_my_account: enqueue storage cleanup, then remove rows.
CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not signed in' USING ERRCODE = '42501';
  END IF;

  -- Capture storage paths while asset rows still exist.
  PERFORM public.enqueue_storage_cleanup(uid);

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
END $$;
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMIT;
