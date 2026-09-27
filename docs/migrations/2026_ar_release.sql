-- =============================================================================
-- Locolo AR Release — Consolidated WS1 migration
-- Project: zvrrbtiqsyzkyixbsybf (PROD — no branching on this plan)
-- Author: generated 2026-09-27
--
-- SAFETY NOTES
--   * All public tables currently have 0 rows — no data to lose.
--   * Sections 1–8 are ADDITIVE and idempotent (ADD COLUMN IF NOT EXISTS /
--     CREATE ... IF NOT EXISTS / CREATE OR REPLACE). Safe to run on prod.
--   * Section 9 is the ONLY destructive step: DROP FUNCTION
--     get_nearby_assets_full(...) then CREATE. The pre-migration body is
--     preserved in the header comment of that section for rollback.
--   * Swift DigitalAsset (Locolo/Models/DigitalAsset.swift) is already in
--     lockstep for the WS1.1 columns (all optional). Quaternion cols (WS2)
--     are decoded-as-ignored until the Swift model gains those properties.
--   * get_recommended_assets (WS1.6/WS5) is intentionally DEFERRED to the WS5
--     migration — it can't be exercised until the embedding pipeline exists.
--     The pgvector COLUMNS are created now so the 1536 dimension is locked in.
-- =============================================================================


-- =============================================================================
-- SECTION 1 — WS1.1  digital_assets: animation + trigger columns (pending)
-- =============================================================================
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS animation_name  text,
  ADD COLUMN IF NOT EXISTS animation_index integer,
  ADD COLUMN IF NOT EXISTS trigger_type    text,
  ADD COLUMN IF NOT EXISTS trigger_config  jsonb;

-- Constrain trigger_type to the four supported triggers (nullable = legacy/none).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'digital_assets_trigger_type_check'
  ) THEN
    ALTER TABLE public.digital_assets
      ADD CONSTRAINT digital_assets_trigger_type_check
      CHECK (trigger_type IS NULL OR trigger_type = ANY (ARRAY['tap','proximity','speech','shake']));
  END IF;
END $$;


-- =============================================================================
-- SECTION 2 — WS1.1  locations: altitude columns (pending)
-- (locations.address already exists — no change needed for it.)
-- =============================================================================
ALTER TABLE public.locations
  ADD COLUMN IF NOT EXISTS altitude_m          double precision,
  ADD COLUMN IF NOT EXISTS altitude_accuracy_m double precision;


-- =============================================================================
-- SECTION 3 — WS1.1  asset_views table
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.asset_views (
  user_id  uuid NOT NULL REFERENCES public.users(user_id)          ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  seen_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, asset_id)
);
CREATE INDEX IF NOT EXISTS asset_views_asset_idx ON public.asset_views(asset_id);


-- =============================================================================
-- SECTION 4 — WS1.2  digital_assets: rotation quaternion + heading accuracy
-- All nullable → legacy Euler rows keep working (viewer falls back to Euler).
-- =============================================================================
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS rot_qx double precision,
  ADD COLUMN IF NOT EXISTS rot_qy double precision,
  ADD COLUMN IF NOT EXISTS rot_qz double precision,
  ADD COLUMN IF NOT EXISTS rot_qw double precision,
  ADD COLUMN IF NOT EXISTS heading_accuracy_deg double precision;


-- =============================================================================
-- SECTION 5 — WS1.4  users: X25519 public key for E2E chat
-- =============================================================================
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS x25519_public_key text,   -- base64 raw 32-byte Curve25519 KA public key
  ADD COLUMN IF NOT EXISTS key_updated_at    timestamptz;


-- =============================================================================
-- SECTION 6 — WS1.5  asset_hype table
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.asset_hype (
  user_id    uuid NOT NULL REFERENCES public.users(user_id)          ON DELETE CASCADE,
  asset_id   uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, asset_id)
);


-- =============================================================================
-- SECTION 7 — WS1.3 (ADAPTED)  Follow counts over the EXISTING follows table
-- Existing schema: follows(follower_id, followee_id, status, updated_at).
-- Decision: adapt, do NOT drop/replace. status='accepted' == an active follow.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user uuid)
RETURNS TABLE(followers bigint, following bigint) LANGUAGE sql STABLE AS $$
  SELECT
    (SELECT count(*) FROM public.follows WHERE followee_id = p_user AND status = 'accepted'),
    (SELECT count(*) FROM public.follows WHERE follower_id = p_user AND status = 'accepted');
$$;


-- =============================================================================
-- SECTION 8 — WS1.6  pgvector columns (dimension LOCKED to 1536 =
--             OpenAI text-embedding-3-small). Additive; embeddings backfilled
--             + get_recommended_assets come in the WS5 migration.
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS embedding       vector(1536),
  ADD COLUMN IF NOT EXISTS embedding_model text,
  ADD COLUMN IF NOT EXISTS search_tsv tsvector
    GENERATED ALWAYS AS (
      to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,''))
    ) STORED;

CREATE INDEX IF NOT EXISTS digital_assets_embedding_idx
  ON public.digital_assets USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS digital_assets_tsv_idx
  ON public.digital_assets USING gin (search_tsv);

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS taste_embedding  vector(1536),
  ADD COLUMN IF NOT EXISTS taste_updated_at timestamptz;


-- =============================================================================
-- SECTION 9 — WS1.1  [[ DESTRUCTIVE ]]  Recreate get_nearby_assets_full
--   Must run AFTER sections 1, 2, 4 (adds the columns it now returns).
--
--   ROLLBACK — pre-migration definition (verified live 2026-09-27):
--     RETURNS TABLE(asset_id uuid, name text, user_id uuid, location_id uuid,
--       file_url text, thumb_url text, file_type text, category text,
--       description text, hype_count integer, view_count integer,
--       created_at timestamptz, panorama_url text, visibility text,
--       interaction_type text, rotation_x/y/z double precision,
--       scale_x/y/z double precision, is_for_sale boolean, accepts_offers boolean,
--       current_value numeric, bought_price numeric, highest_offer numeric,
--       active_offers integer, location_name text, latitude/longitude double precision)
--     — plain SELECT da.*, l.name, ST_Y/ST_X(l.geom) with a single ST_DWithin
--       filter and JOIN locations. No offer subqueries, no visibility filter.
-- =============================================================================
DROP FUNCTION IF EXISTS public.get_nearby_assets_full(double precision, double precision, double precision);

CREATE FUNCTION public.get_nearby_assets_full(
  p_lat double precision,
  p_lon double precision,
  p_radius_meters double precision
)
RETURNS TABLE(
  asset_id uuid, name text, user_id uuid, location_id uuid,
  file_url text, thumb_url text, file_type text, category text, description text,
  hype_count integer, view_count integer, created_at timestamp with time zone,
  panorama_url text, visibility text, interaction_type text,
  rotation_x double precision, rotation_y double precision, rotation_z double precision,
  scale_x double precision, scale_y double precision, scale_z double precision,
  is_for_sale boolean, accepts_offers boolean,
  current_value numeric, bought_price numeric, highest_offer numeric, active_offers integer,
  location_name text, latitude double precision, longitude double precision,
  -- NEW (WS1.1): address + altitude + animation + trigger
  address text, altitude_m double precision,
  animation_name text, animation_index integer, trigger_type text, trigger_config jsonb,
  -- NEW (WS1.2): rotation quaternion + heading accuracy
  rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision,
  heading_accuracy_deg double precision
)
LANGUAGE sql
AS $function$
    SELECT
        da.asset_id,
        da.name,
        da.user_id,
        da.location_id,
        da.file_url,
        da.thumb_url,
        da.file_type,
        da.category,
        da.description,
        da.hype_count,
        da.view_count,
        da.created_at,
        da.panorama_url,
        da.visibility,
        da.interaction_type,

        da.rotation_x,
        da.rotation_y,
        da.rotation_z,
        da.scale_x,
        da.scale_y,
        da.scale_z,

        da.is_for_sale,
        da.accepts_offers,
        da.current_value,
        da.bought_price,
        da.highest_offer,
        da.active_offers,

        l.name AS location_name,
        ST_Y(l.geom::geometry) AS latitude,
        ST_X(l.geom::geometry) AS longitude,

        -- NEW (WS1.1)
        l.address,
        l.altitude_m,
        da.animation_name,
        da.animation_index,
        da.trigger_type,
        da.trigger_config,

        -- NEW (WS1.2)
        da.rot_qx,
        da.rot_qy,
        da.rot_qz,
        da.rot_qw,
        da.heading_accuracy_deg
    FROM digital_assets da
    JOIN locations l ON da.location_id = l.location_id
    WHERE ST_DWithin(
        l.geom::geography,
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
        p_radius_meters
    );
$function$;

-- =============================================================================
-- END
-- =============================================================================
