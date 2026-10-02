-- =============================================================================
-- 2026_v3_storage_paths.sql — own-folder writes for V3 uploads in `media`.
--
-- MemoryStore / PostStore upload to
--   media/memories/<auth.uid>/<uuid>.jpg | .mp4 | _thumb.jpg
--   media/posts/<auth.uid>/<uuid>.jpg
-- The existing permissive policy "Allow authenticated uploads 1ps738_0" lets
-- any signed-in user INSERT anywhere in `media` (the legacy app uploads there
-- under other prefixes), so it is left alone. These RESTRICTIVE policies are
-- AND-ed with it: under memories/ and posts/ the second path segment must be
-- the caller's uid. Other prefixes and other buckets are unaffected.
-- Idempotent.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS v3_media_own_folder_insert ON storage.objects;
DROP POLICY IF EXISTS v3_media_own_folder_update ON storage.objects;

CREATE POLICY v3_media_own_folder_insert ON storage.objects
  AS RESTRICTIVE FOR INSERT TO public
  WITH CHECK (
    bucket_id <> 'media'
    OR coalesce((storage.foldername(name))[1], '') NOT IN ('memories', 'posts')
    OR (storage.foldername(name))[2] = (select auth.uid())::text
  );

CREATE POLICY v3_media_own_folder_update ON storage.objects
  AS RESTRICTIVE FOR UPDATE TO public
  USING (
    bucket_id <> 'media'
    OR coalesce((storage.foldername(name))[1], '') NOT IN ('memories', 'posts')
    OR (storage.foldername(name))[2] = (select auth.uid())::text
  )
  WITH CHECK (
    bucket_id <> 'media'
    OR coalesce((storage.foldername(name))[1], '') NOT IN ('memories', 'posts')
    OR (storage.foldername(name))[2] = (select auth.uid())::text
  );

COMMIT;
