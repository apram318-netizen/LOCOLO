-- =============================================================================
-- Locolo — canonical dump of the read/RPC functions LIVE in prod
-- Project: zvrrbtiqsyzkyixbsybf · captured 2026-09-27 via pg_get_functiondef
--
-- Purpose: version-control the functions that were applied directly to prod
-- (some were created via MCP and never lived in a migration file). Re-running
-- this file reproduces the current prod definitions exactly.
--
-- ⚠️ INVARIANT: get_nearby_assets_full, get_recommended_assets and get_asset_full
-- MUST return the SAME 41 columns that DigitalAsset.CodingKeys decodes (Swift
-- lockstep). If you add a column to one, add it to all three + the Swift model.
--
-- NOTE: get_comment_counts is NOT here — it ships with 2026_ar_social.sql, which
-- is not yet applied to prod.
--
-- NOTE: the safety/hardening migration flips these read RPCs to SECURITY INVOKER
-- so RLS visibility (da_select) applies. This dump reflects the pre-hardening
-- state (SECURITY DEFINER / default). Apply 2026_ar_safety_and_hardening.sql
-- after this to enforce visibility.
-- =============================================================================


-- get_nearby_assets_full — assets within a radius (WS1). 41-col shape.
CREATE OR REPLACE FUNCTION public.get_nearby_assets_full(p_lat double precision, p_lon double precision, p_radius_meters double precision)
 RETURNS TABLE(asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text, file_type text, category text, description text, hype_count integer, view_count integer, created_at timestamp with time zone, panorama_url text, visibility text, interaction_type text, rotation_x double precision, rotation_y double precision, rotation_z double precision, scale_x double precision, scale_y double precision, scale_z double precision, is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric, highest_offer numeric, active_offers integer, location_name text, latitude double precision, longitude double precision, address text, altitude_m double precision, animation_name text, animation_index integer, trigger_type text, trigger_config jsonb, rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision, heading_accuracy_deg double precision)
 LANGUAGE sql
AS $function$
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
        da.rot_qx, da.rot_qy, da.rot_qz, da.rot_qw, da.heading_accuracy_deg
    FROM digital_assets da
    JOIN locations l ON da.location_id = l.location_id
    WHERE ST_DWithin(
        l.geom::geography,
        ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography,
        p_radius_meters
    );
$function$;


-- get_asset_full — one asset by id (deep links). 41-col shape.
CREATE OR REPLACE FUNCTION public.get_asset_full(p_asset_id uuid)
 RETURNS TABLE(asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text, file_type text, category text, description text, hype_count integer, view_count integer, created_at timestamp with time zone, panorama_url text, visibility text, interaction_type text, rotation_x double precision, rotation_y double precision, rotation_z double precision, scale_x double precision, scale_y double precision, scale_z double precision, is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric, highest_offer numeric, active_offers integer, location_name text, latitude double precision, longitude double precision, address text, altitude_m double precision, animation_name text, animation_index integer, trigger_type text, trigger_config jsonb, rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision, heading_accuracy_deg double precision)
 LANGUAGE sql
 STABLE
AS $function$
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
        da.rot_qx, da.rot_qy, da.rot_qz, da.rot_qw, da.heading_accuracy_deg
    FROM digital_assets da
    LEFT JOIN locations l ON da.location_id = l.location_id
    WHERE da.asset_id = p_asset_id;
$function$;


-- get_recommended_assets — semantic + engagement + proximity + recency + follow
-- ranked feed (WS5). p_query_embedding NULL = personalized (taste vector).
CREATE OR REPLACE FUNCTION public.get_recommended_assets(p_user uuid, p_lat double precision, p_lon double precision, p_radius_meters double precision DEFAULT 50000, p_query_embedding vector DEFAULT NULL::vector, p_limit integer DEFAULT 60)
 RETURNS TABLE(asset_id uuid, name text, user_id uuid, location_id uuid, file_url text, thumb_url text, file_type text, category text, description text, hype_count integer, view_count integer, created_at timestamp with time zone, panorama_url text, visibility text, interaction_type text, rotation_x double precision, rotation_y double precision, rotation_z double precision, scale_x double precision, scale_y double precision, scale_z double precision, is_for_sale boolean, accepts_offers boolean, current_value numeric, bought_price numeric, highest_offer numeric, active_offers integer, location_name text, latitude double precision, longitude double precision, address text, altitude_m double precision, animation_name text, animation_index integer, trigger_type text, trigger_config jsonb, rot_qx double precision, rot_qy double precision, rot_qz double precision, rot_qw double precision, heading_accuracy_deg double precision)
 LANGUAGE sql
 STABLE
AS $function$
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
    rot_qx, rot_qy, rot_qz, rot_qw, heading_accuracy_deg
  FROM scored
  ORDER BY (0.45 * semantic + 0.20 * engagement + 0.20 * proximity + 0.15 * recency + follow_boost) DESC,
           created_at DESC
  LIMIT p_limit;
$function$;


-- get_follow_counts — accepted followers / following counts (WS4).
CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user uuid)
 RETURNS TABLE(followers bigint, following bigint)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    (SELECT count(*) FROM public.follows WHERE followee_id = p_user AND status = 'accepted'),
    (SELECT count(*) FROM public.follows WHERE follower_id = p_user AND status = 'accepted');
$function$;


-- toggle_asset_hype — atomic hype toggle + hype_count sync (WS5.4).
CREATE OR REPLACE FUNCTION public.toggle_asset_hype(p_user uuid, p_asset uuid)
 RETURNS TABLE(hyped boolean, hype_count integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
  removed boolean;
BEGIN
  DELETE FROM public.asset_hype WHERE user_id = p_user AND asset_id = p_asset;
  removed := FOUND;

  IF removed THEN
    UPDATE public.digital_assets
      SET hype_count = GREATEST(COALESCE(digital_assets.hype_count, 0) - 1, 0)
      WHERE asset_id = p_asset;
  ELSE
    INSERT INTO public.asset_hype(user_id, asset_id) VALUES (p_user, p_asset);
    UPDATE public.digital_assets
      SET hype_count = COALESCE(digital_assets.hype_count, 0) + 1
      WHERE asset_id = p_asset;
  END IF;

  RETURN QUERY
    SELECT NOT removed, COALESCE(da.hype_count, 0)
    FROM public.digital_assets da WHERE da.asset_id = p_asset;
END;
$function$;
