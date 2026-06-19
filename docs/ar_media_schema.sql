-- AR asset sidecar media support.
-- Run this in Supabase before saving AR assets with attached audio/video.

alter table public.digital_assets
  add column if not exists media_url text,
  add column if not exists media_type text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'digital_assets_media_type_check'
  ) then
    alter table public.digital_assets
      add constraint digital_assets_media_type_check
      check (media_type is null or media_type in ('audio', 'video'));
  end if;
end $$;

-- If digital_assets_flat is a manually maintained view, update it so it
-- exposes media_url and media_type alongside file_url/file_type/thumb_url.
