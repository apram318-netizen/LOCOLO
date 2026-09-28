-- =============================================================================
-- LOCOLO V2 — Add optional owner_id to DigitalAsset read RPCs
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet (status §5.26).
-- Appends owner_id to get_nearby_assets_full / get_asset_full /
-- get_recommended_assets. Swift already decodes owner_id optionally.
-- Apply after Phase A (owner_id column exists). SECURITY INVOKER so RLS applies.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_nearby_assets_full(
  p_lat double precision, p_lon double precision, p_radius_meters double precision
)
RETURNS TABLE(
  asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text,
  file_type text, category text, description text, hype_count integer, view_count integer,
  created_at timestamptz, panorama_url text, visibility text, interaction_type text,
  rotation_x double precision, rotation_y double precision, rotation_z double precision,
  scale_x double precision, scale_y double precision, scale_z double precision,
  is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric,
  highest_offer numeric, active_offers integer, location_name text, latitude double precision,
  longitude double precision, address text, altitude_m double precision, animation_name text,
  animation_index integer, trigger_type text, trigger_config jsonb,
  rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision,
  heading_accuracy_deg double precision, owner_id uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT
    da.asset_id, da.name, da.user_id, da.location_id,
    da.file_url, da.thumb_url, da.file_type, da.category, da.description,
    da.hype_count, da.view_count, da.created_at,
    da.panorama_url, da.visibility, da.interaction_type,
    da.rotation_x, da.rotation_y, da.rotation_z,
    da.scale_x, da.scale_y, da.scale_z,
    da.is_for_sale, da.accepts_offers,
    da.current_value, da.bought_price, da.highest_offer, da.active_offers,
    l.name AS location_name,
    ST_Y(l.geom::geometry) AS latitude,
    ST_X(l.geom::geometry) AS longitude,
    l.address, l.altitude_m,
    da.animation_name, da.animation_index, da.trigger_type, da.trigger_config,
    da.rot_qx, da.rot_qy, da.rot_qz, da.rot_qw, da.heading_accuracy_deg,
    da.owner_id
  FROM digital_assets da
  JOIN locations l ON da.location_id = l.location_id
  WHERE ST_DWithin(
    l.geom::geography,
    ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
    p_radius_meters
  );
$$;

CREATE OR REPLACE FUNCTION public.get_asset_full(p_asset_id uuid)
RETURNS TABLE(
  asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text,
  file_type text, category text, description text, hype_count integer, view_count integer,
  created_at timestamptz, panorama_url text, visibility text, interaction_type text,
  rotation_x double precision, rotation_y double precision, rotation_z double precision,
  scale_x double precision, scale_y double precision, scale_z double precision,
  is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric,
  highest_offer numeric, active_offers integer, location_name text, latitude double precision,
  longitude double precision, address text, altitude_m double precision, animation_name text,
  animation_index integer, trigger_type text, trigger_config jsonb,
  rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision,
  heading_accuracy_deg double precision, owner_id uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  SELECT
    da.asset_id, da.name, da.user_id, da.location_id,
    da.file_url, da.thumb_url, da.file_type, da.category, da.description,
    da.hype_count, da.view_count, da.created_at,
    da.panorama_url, da.visibility, da.interaction_type,
    da.rotation_x, da.rotation_y, da.rotation_z,
    da.scale_x, da.scale_y, da.scale_z,
    da.is_for_sale, da.accepts_offers,
    da.current_value, da.bought_price, da.highest_offer, da.active_offers,
    l.name AS location_name,
    ST_Y(l.geom::geometry) AS latitude,
    ST_X(l.geom::geometry) AS longitude,
    l.address, l.altitude_m,
    da.animation_name, da.animation_index, da.trigger_type, da.trigger_config,
    da.rot_qx, da.rot_qy, da.rot_qz, da.rot_qw, da.heading_accuracy_deg,
    da.owner_id
  FROM digital_assets da
  LEFT JOIN locations l ON da.location_id = l.location_id
  WHERE da.asset_id = p_asset_id;
$$;

-- Recommended feed: keep ranking logic, append owner_id to output.
CREATE OR REPLACE FUNCTION public.get_recommended_assets(
  p_user uuid, p_lat double precision, p_lon double precision,
  p_radius_meters double precision DEFAULT 50000,
  p_query_embedding vector DEFAULT NULL::vector,
  p_limit integer DEFAULT 60
)
RETURNS TABLE(
  asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text,
  file_type text, category text, description text, hype_count integer, view_count integer,
  created_at timestamptz, panorama_url text, visibility text, interaction_type text,
  rotation_x double precision, rotation_y double precision, rotation_z double precision,
  scale_x double precision, scale_y double precision, scale_z double precision,
  is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric,
  highest_offer numeric, active_offers integer, location_name text, latitude double precision,
  longitude double precision, address text, altitude_m double precision, animation_name text,
  animation_index integer, trigger_type text, trigger_config jsonb,
  rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision,
  heading_accuracy_deg double precision, owner_id uuid
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public AS $$
  WITH pref AS (
    SELECT taste_embedding FROM public.users WHERE user_id = p_user
  ),
  base AS (
    SELECT da.*,
           l.name AS l_location_name,
           ST_Y(l.geom::geometry) AS l_lat,
           ST_X(l.geom::geometry) AS l_lon,
           l.address AS l_address,
           l.altitude_m AS l_altitude_m,
           ST_Distance(l.geom::geography,
                       ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography) AS dist_m
    FROM public.digital_assets da
    JOIN public.locations l ON da.location_id = l.location_id
    WHERE ST_DWithin(l.geom::geography,
                     ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
                     p_radius_meters)
  ),
  scored AS (
    SELECT b.*,
      CASE
        WHEN b.embedding IS NOT NULL
             AND COALESCE(p_query_embedding, (SELECT taste_embedding FROM pref)) IS NOT NULL
        THEN 1 - (b.embedding <=> COALESCE(p_query_embedding, (SELECT taste_embedding FROM pref)))
        ELSE 0
      END AS semantic,
      GREATEST(0, 1 - (b.dist_m / NULLIF(p_radius_meters, 0))) AS proximity,
      LEAST(1.0, (COALESCE(b.hype_count, 0) + COALESCE(b.view_count, 0)) / 100.0) AS engagement,
      GREATEST(0, 1 - (EXTRACT(EPOCH FROM (now() - b.created_at)) / 86400.0) / 30.0) AS recency,
      CASE WHEN EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = p_user AND f.followee_id = b.user_id AND f.status = 'accepted'
      ) THEN 0.10 ELSE 0 END AS follow_boost
    FROM base b
  )
  SELECT
    asset_id, name, user_id, location_id, file_url, thumb_url, file_type, category, description,
    hype_count, view_count, created_at, panorama_url, visibility, interaction_type,
    rotation_x, rotation_y, rotation_z, scale_x, scale_y, scale_z,
    is_for_sale, accepts_offers, current_value, bought_price, highest_offer, active_offers,
    l_location_name AS location_name, l_lat AS latitude, l_lon AS longitude,
    l_address AS address, l_altitude_m AS altitude_m,
    animation_name, animation_index, trigger_type, trigger_config,
    rot_qx, rot_qy, rot_qz, rot_qw, heading_accuracy_deg,
    owner_id
  FROM scored
  ORDER BY (0.45 * semantic + 0.20 * engagement + 0.20 * proximity + 0.15 * recency + follow_boost) DESC,
           created_at DESC
  LIMIT p_limit;
$$;

COMMIT;
