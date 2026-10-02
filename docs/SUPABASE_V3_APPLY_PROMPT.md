You're working on **Locolo**, a native SwiftUI iOS app (code in `~/Desktop/LOCOLO/locolo`) with a Supabase backend: project ref **`zvrrbtiqsyzkyixbsybf`**, Postgres + PostGIS + RLS. The Supabase MCP server is configured for this project. Use its tools (list_tables, execute_sql, apply_migration, get_advisors, …). If they don't show up, tell me to run `/mcp` → supabase → Authenticate and stop.

## Goal
Apply two migrations that were written in the last session but never run (that session had no database access), then check that the iOS client's assumptions hold against the live schema.

1. `docs/migrations/2026_v3_offers_fix.sql`: fixes accepting/rejecting offers, which currently fails with `new row for relation "offers" violates check constraint "offers_status_check"`. It normalizes existing `offers.status` values, recreates the CHECK as (pending, accepted, rejected, withdrawn, expired) and adds `respond_to_offer(p_offer uuid, p_accept boolean)`. That function is SECURITY DEFINER with an explicit asset-owner check; it rejects competing pending offers and recomputes `active_offers`/`highest_offer`.
2. `docs/migrations/2026_v3_memories_posts_growth.sql`: tables `asset_memories`, `memory_likes`, `memory_views`, `posts`, `post_likes` (all RLS); RPCs `get_memories`, `get_posts`, `get_asset_growth` (owner-only, SECURITY DEFINER), `update_asset_settings`, `get_asset_alerts`; new columns `digital_assets.alert_audio_url` and `alert_radius_m`.

Read `docs/LOCOLO_V3_FEEDBACK.md` for the feature context and `docs/LOCOLO_V2_SECURITY.md` for the security model before changing anything.

## Steps
1. **Inspect before writing.** Run read-only queries against the live DB:
   - the current definition of `offers_status_check` (`pg_get_constraintdef`) and `SELECT status, count(*) FROM offers GROUP BY 1`;
   - the columns of `offers`, `digital_assets`, `users`, `follows` (or whatever the follow table is called), and any block/mute table;
   - existing functions with the same names.
   The SQL was written against the *documented* schema, not the live one. Compare every table and column each migration references (e.g. offer columns like `offer_id`/`asset_id`/`buyer_id`/`amount`, `digital_assets.owner_id`/`creator_id`/`accepting_offers`/`active_offers`/`highest_offer`, view/like/offer tables used by `get_asset_growth`, and the follow/block tables used in RLS visibility) and fix any mismatched names **in the migration files** before applying them. Show me a short diff summary of what you changed.
2. **Apply** `2026_v3_offers_fix.sql` first, then `2026_v3_memories_posts_growth.sql`, each with `apply_migration` (names `v3_offers_fix` and `v3_memories_posts_growth`). If a statement fails, fix the file and re-apply; both are meant to be idempotent. Anything that uses PostGIS types needs `search_path = public, extensions`.
3. **Storage.** The client uploads to the **`media`** bucket (`Locolo/Models/Controllers/ObjStorageManager.swift`) at `memories/<auth.uid>/<uuid>.jpg|.mp4|_thumb.jpg` and `posts/<auth.uid>/<uuid>.jpg`, then uses public URLs. Check the `storage.objects` policies on `media`. If authenticated users can't insert under those prefixes, add policies that only allow writes where the second path segment = `auth.uid()::text`. Put them in a new file `docs/migrations/2026_v3_storage_paths.sql` and apply it.
4. **Verify:**
   - `offers_status_check` now allows accepted/rejected; `respond_to_offer` exists, is granted to `authenticated` only and is not executable by `anon`.
   - All new tables have RLS enabled. `get_advisors` (security + performance) shows no new errors on the V3 objects; fix any it reports.
   - Every new function has a pinned `search_path`. SECURITY DEFINER functions check ownership themselves.
   - Smoke-test inside a transaction you **ROLLBACK**: as an asset owner (`set local role authenticated; set local request.jwt.claims = '{"sub":"<owner uuid>"}'`), accept a pending offer and confirm the status changes and competing offers are rejected. Do this only if a real asset owner with a pending offer exists; otherwise skip and say so.
   - Check the client's decoding: the RPC return columns must match the Swift models in `Locolo/ARModule/Services/MemoryStore.swift` (`AssetMemory`), `PostStore.swift` (`UserPost`, `PostMedia`), `Dashboard/AssetManageSheet.swift` (growth series) and `Services/BackgroundExploreService.swift` (`asset_id`, `alert_audio_url`, `alert_radius_m`). If you must rename something, change the SQL, not the Swift, unless the Swift is clearly wrong; then rebuild with `xcodebuild -project Locolo.xcodeproj -scheme Locolo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
5. **Update docs:** mark owner actions #1 and #2 as done in `docs/LOCOLO_V3_FEEDBACK.md`, note any schema fixes you made, and update the project memory file `locolo-ar-module.md`.

## Hard rules (project invariants)
- Never `DROP` data-bearing tables or columns, or `TRUNCATE`/`DELETE` user data. Ask me first if a fix seems to need it.
- The `DigitalAsset` Swift model and the `get_*_full` asset RPCs return the same 42 columns in lockstep. Do **not** change those RPCs' return shape in this task.
- Never `select *` from `users` (it has private columns); read RPCs are SECURITY INVOKER.
- Notifications are written only by DB triggers, never by the client.
- Don't commit or push with git unless I ask. If I do, push only to the `github` remote, never `origin`.

## Not SQL: tell me afterwards which of these are still open
- Auth → Email templates: "Confirm signup" and "Magic Link" must include `{{ .Token }}` (the app uses 6-digit codes).
- Auth → SMTP: set up a custom sender. The built-in one barely delivers.
- Auth → Providers: Apple + Google enabled; add redirect URL `locolo://login-callback`.
If the MCP can read these auth settings, report their current state. Don't change provider secrets yourself.

End with a short report: what was applied, what you changed in the SQL and why, verification results, and anything left for me.
