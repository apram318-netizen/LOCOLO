-- =============================================================================
-- Locolo AR — Fix: digital_assets_flat must enforce the caller's RLS
--
-- Run AFTER 2026_ar_safety_and_hardening.sql. Idempotent.
--
-- digital_assets_flat is the app's primary feed read path
-- (DigitalAssetRepository.fetchAll selects from it). By default a Postgres view
-- runs SECURITY DEFINER (view owner's rights), which BYPASSES the da_select
-- visibility policy — so private/friends assets would leak through the feed
-- even though direct digital_assets reads are protected. Supabase's security
-- advisor flags this as an ERROR (0010_security_definer_view).
--
-- security_invoker = on makes the view evaluate underlying-table RLS as the
-- querying user, so visibility is enforced consistently everywhere.
-- =============================================================================

ALTER VIEW public.digital_assets_flat SET (security_invoker = on);
