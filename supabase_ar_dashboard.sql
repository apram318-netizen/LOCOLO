-- AR Dashboard schema changes
-- Run in the Supabase SQL editor BEFORE shipping the app update.
-- New Swift fields are optionals, so old data and the old RPC degrade gracefully,
-- but animations/triggers/addresses only work once this is applied.

-- 1. Poster altitude for precise AR geo-anchoring
ALTER TABLE public.locations
  ADD COLUMN IF NOT EXISTS altitude_m double precision,
  ADD COLUMN IF NOT EXISTS altitude_accuracy_m double precision;

-- 2. Selected embedded-USDZ animation (index is the reliable key; names are
--    often empty in exported USDZs, so both are stored)
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS animation_name text,
  ADD COLUMN IF NOT EXISTS animation_index integer;

-- 3. One trigger per asset, chosen at post time
--    trigger_config shapes:
--      tap:       {}
--      proximity: {"distance_m": 10}
--      speech:    {"phrase": "open sesame"}
--      shake:     {"shake_pattern": "single" | "double" | "tilt"}
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS trigger_type text
    CHECK (trigger_type IN ('tap','proximity','speech','shake')),
  ADD COLUMN IF NOT EXISTS trigger_config jsonb;

-- 4. Per-user record of assets explored/seen in AR sessions.
--    Written (upserted) by the app whenever someone else's asset is placed
--    in the viewer's AR session; read back as the "Explored" tab of the
--    AR dashboard profile. The FK is required for the PostgREST embed
--    select("seen_at, digital_assets(*)") the app uses.
CREATE TABLE IF NOT EXISTS public.asset_views (
  user_id uuid NOT NULL,
  asset_id uuid NOT NULL REFERENCES public.digital_assets (asset_id) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, asset_id)
);

CREATE INDEX IF NOT EXISTS asset_views_user_seen_idx
  ON public.asset_views (user_id, seen_at DESC);

-- 5. The nearby-assets RPC must return the six new columns.
--    First dump the CURRENT definition so you keep your existing body
--    (offer subqueries, visibility filters, etc.):
--
--      SELECT pg_get_functiondef(
--        'get_nearby_assets_full(double precision,double precision,double precision)'::regprocedure
--      );
--
--    Then re-create it, appending these columns to BOTH the RETURNS TABLE
--    list and the SELECT list (l = locations join, da = digital_assets):
--
--      ... RETURNS TABLE (
--            ...existing columns...,
--            address text,
--            altitude_m double precision,
--            animation_name text,
--            animation_index integer,
--            trigger_type text,
--            trigger_config jsonb
--          )
--      ...
--      SELECT ...existing select list...,
--             l.address,
--             l.altitude_m,
--             da.animation_name,
--             da.animation_index,
--             da.trigger_type,
--             da.trigger_config
--      FROM digital_assets da
--      JOIN locations l ON l.location_id = da.location_id
--      ...
--
--    Note: PostgreSQL cannot ALTER a function's return type — you must
--    DROP FUNCTION get_nearby_assets_full(double precision,double precision,double precision);
--    and CREATE it again with the merged definition.
