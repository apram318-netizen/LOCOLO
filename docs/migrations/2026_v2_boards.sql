-- =============================================================================
-- LOCOLO V2 Phase D — Boards (Pinterest-style collections)
--
-- CLAUDE: ACTION REQUIRED — this file is NOT applied to prod yet.
-- Owner deferred: paste into Supabase SQL Editor and Run (status §5.12).
-- Until then BoardsStore hides boards UI (client degrades gracefully).
--
-- Spec name "collections" → table `boards` (avoids clash with owned-asset
-- "My Collection" in the app). Idempotent. Run after V1 social migration.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.boards (
  board_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  title       text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 60),
  description text CHECK (description IS NULL OR char_length(description) <= 280),
  visibility  text NOT NULL DEFAULT 'private'
                CHECK (visibility IN ('public', 'friends', 'private')),
  cover_url   text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boards_owner_idx ON public.boards (owner_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS boards_public_idx ON public.boards (updated_at DESC)
  WHERE visibility = 'public';

ALTER TABLE public.boards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS boards_select ON public.boards;
DROP POLICY IF EXISTS boards_insert_self ON public.boards;
DROP POLICY IF EXISTS boards_update_self ON public.boards;
DROP POLICY IF EXISTS boards_delete_self ON public.boards;

CREATE POLICY boards_select ON public.boards FOR SELECT TO authenticated
  USING (
    owner_id = auth.uid()
    OR visibility = 'public'
    OR (
      visibility = 'friends'
      AND EXISTS (
        SELECT 1 FROM public.follows f
         WHERE f.follower_id = auth.uid()
           AND f.followee_id = boards.owner_id
           AND f.status = 'accepted')
    )
  );
CREATE POLICY boards_insert_self ON public.boards FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = owner_id);
CREATE POLICY boards_update_self ON public.boards FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY boards_delete_self ON public.boards FOR DELETE TO authenticated
  USING (auth.uid() = owner_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.boards TO authenticated;

CREATE TABLE IF NOT EXISTS public.board_items (
  board_id   uuid NOT NULL REFERENCES public.boards(board_id) ON DELETE CASCADE,
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  added_by   uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  note       text CHECK (note IS NULL OR char_length(note) <= 200),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (board_id, asset_id)
);
CREATE INDEX IF NOT EXISTS board_items_asset_idx ON public.board_items (asset_id);
CREATE INDEX IF NOT EXISTS board_items_board_idx ON public.board_items (board_id, created_at DESC);

ALTER TABLE public.board_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bi_select ON public.board_items;
DROP POLICY IF EXISTS bi_insert_owner ON public.board_items;
DROP POLICY IF EXISTS bi_delete_owner ON public.board_items;

-- Readable if the board is readable AND the asset is readable (da_select).
CREATE POLICY bi_select ON public.board_items FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.boards b WHERE b.board_id = board_items.board_id)
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = board_items.asset_id)
  );
CREATE POLICY bi_insert_owner ON public.board_items FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = added_by
    AND EXISTS (
      SELECT 1 FROM public.boards b
       WHERE b.board_id = board_items.board_id AND b.owner_id = auth.uid())
    AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = board_items.asset_id)
  );
CREATE POLICY bi_delete_owner ON public.board_items FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.boards b
       WHERE b.board_id = board_items.board_id AND b.owner_id = auth.uid())
  );

GRANT SELECT, INSERT, DELETE ON public.board_items TO authenticated;

-- Touch boards.updated_at when items change.
CREATE OR REPLACE FUNCTION public.touch_board_updated_at()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.boards
     SET updated_at = now()
   WHERE board_id = COALESCE(NEW.board_id, OLD.board_id);
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS board_items_touch ON public.board_items;
CREATE TRIGGER board_items_touch
  AFTER INSERT OR DELETE ON public.board_items
  FOR EACH ROW EXECUTE FUNCTION public.touch_board_updated_at();

-- List boards for a user (own always; others only if visible to caller).
CREATE OR REPLACE FUNCTION public.get_user_boards(p_user uuid, p_limit int DEFAULT 40)
RETURNS TABLE(
  board_id uuid, owner_id uuid, title text, description text, visibility text,
  cover_url text, item_count int, created_at timestamptz, updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT b.board_id, b.owner_id, b.title, b.description, b.visibility,
         COALESCE(b.cover_url, (
           SELECT d.thumb_url FROM public.board_items i
           JOIN public.digital_assets d ON d.asset_id = i.asset_id
           WHERE i.board_id = b.board_id
           ORDER BY i.created_at DESC LIMIT 1
         )) AS cover_url,
         (SELECT count(*)::int FROM public.board_items i WHERE i.board_id = b.board_id) AS item_count,
         b.created_at, b.updated_at
    FROM public.boards b
   WHERE b.owner_id = p_user
   ORDER BY b.updated_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 40), 100));
$$;
REVOKE ALL ON FUNCTION public.get_user_boards(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_boards(uuid, int) TO authenticated;

-- Asset ids on a board (newest first). Client loads rows via digital_assets_flat.
CREATE OR REPLACE FUNCTION public.get_board_item_ids(p_board uuid, p_limit int DEFAULT 60)
RETURNS TABLE(asset_id uuid, created_at timestamptz)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT i.asset_id, i.created_at
    FROM public.board_items i
   WHERE i.board_id = p_board
     AND EXISTS (SELECT 1 FROM public.digital_assets d WHERE d.asset_id = i.asset_id)
   ORDER BY i.created_at DESC
   LIMIT greatest(1, least(coalesce(p_limit, 60), 200));
$$;
REVOKE ALL ON FUNCTION public.get_board_item_ids(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_board_item_ids(uuid, int) TO authenticated;

COMMIT;

-- =============================================================================
-- Verify:
--   select * from public.get_user_boards(auth.uid());
-- CLAUDE: apply when convenient — app hides boards if migration missing.
-- =============================================================================
