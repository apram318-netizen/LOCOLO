-- =============================================================================
-- LOCOLO V2 — Extend digital_assets.trigger_type CHECK (§5.28)
--
-- CLAUDE: ACTION REQUIRED — NOT applied to prod yet.
-- Client TriggerType now includes gaze / time_of_day / long_press / multi_tap /
-- walk_around. Prod CHECK from 2026_ar_release.sql only allows the original
-- four — minting with new triggers fails until this runs. Idempotent.
-- =============================================================================

BEGIN;

ALTER TABLE public.digital_assets
  DROP CONSTRAINT IF EXISTS digital_assets_trigger_type_check;

ALTER TABLE public.digital_assets
  ADD CONSTRAINT digital_assets_trigger_type_check
  CHECK (
    trigger_type IS NULL OR trigger_type = ANY (ARRAY[
      'tap', 'proximity', 'speech', 'shake',
      'gaze', 'time_of_day', 'long_press', 'multi_tap', 'walk_around'
    ])
  );

COMMENT ON CONSTRAINT digital_assets_trigger_type_check ON public.digital_assets IS
  'V2 triggers: gaze, time_of_day, long_press, multi_tap, walk_around (+ V1 four).';

COMMIT;
