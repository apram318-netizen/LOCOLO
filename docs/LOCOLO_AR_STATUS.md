# LOCOLO AR — Implementation Status & AI Handoff

> **Audience:** AI coding agents (and humans) picking up this codebase.
> **Companion to:** `docs/LOCOLO_AR_RELEASE_SPEC.md` (the full WS0–WS9 spec — read it for intent; read THIS for what actually exists).
> **Last updated:** 2026-09-27 (stage 5, verification pass) · branch `fresh-start` · simulator build green via `xcodebuild`. Stage 4 + 5 changes are **uncommitted**.

---

## 1. Product state in one paragraph

Locolo is a **standalone AR-only social app** ("Instagram for real life"). Auth → `ARDashboardRootView` (Explore / Nearby / Search / Creator Studio). Users place USDZ assets (or **draw them in the air**) at real GPS coordinates, discover others' assets in an AR viewer with a **radar**, a **hot/cold finder** and **snapshots**, earn an **Explorer Passport**, follow creators, hype assets, get a server-ranked feed, and chat with **end-to-end encryption**. Report/block, settings, sign-out and in-app account deletion exist. Legacy non-AR screens remain in the repo but are off the boot path.

## 2. Workstream status — verified 2026-09-27

"Verified" = read the code and/or probed prod with the anon key (read-only). Earlier versions of this doc marked everything ✅; several claims were wrong and are corrected here.

| WS | Status | Verified facts |
|---|---|---|
| WS0 boot AR-only | ✅ | `ContentView` → `ARAppRootView` → `ARDashboardRootView(isRootExperience: true)`. |
| WS1 DB migration | ✅ applied | Prod has `get_nearby_assets_full` (41 cols), `get_recommended_assets`, `get_asset_full`, `get_follow_counts`, `toggle_asset_hype`. **`get_asset_full` and `toggle_asset_hype` are not in the repo's SQL** — dump them (`pg_get_functiondef`) and commit. Prod has **10 assets / 9 users** (not "0 rows"). |
| WS2 rotation | ✅ code, ⏳ device test | Quaternion-first replay. **Fixed this pass:** legacy Euler values in prod are **radians** (±π) but were read as degrees. No per-asset heading-accuracy column is stored. |
| WS3 resilience | ✅ with fixes | **Fixed:** viewer never restarted on 2nd visit (`session.configuration` stayed non-nil on the shared ARView), ghost/duplicate anchors on re-entry and geo→world fallback, late model loads re-adding dead anchors, heading not started on first permission grant, `automaticallyConfigureSession` racing our config, no re-fetch ever if the first fetch failed (now retried every 20 s). **Added:** tappable mode badge switches Geo ⇄ GPS where geo data exists (remembered in `ar.prefersGPSMode`; also usable while geo is still localizing); GPS mode re-anchors on each 75 m walk refetch (fix ≤ 25 m accuracy) from the camera's current position and moves placed anchors, instead of measuring everything from the session-start fix. ⏳ device test. |
| WS4 social | ✅ with fixes | **Fixed:** profile `errorMessage` now shown with Retry; `.create` no longer falls back to a random `UUID()` owner. **Fixed:** `ARMessagesView` nested a `NavigationStack` inside a pushed route — chats now push `ARRoute.chat` on the dashboard stack via `ARChatScreen`, which owns its `ChatViewModel` (inline construction re-created the view model + Firestore listener on every re-render). **Added:** "On the Map" card on profiles (pins via `digital_assets → locations(latitude, longitude)` embed, tap opens the asset), "Assets" stat scrolls to the grid, and profiles hide private/friends assets client-side to mirror `da_select`. |
| WS5 discovery | ✅ code, ⏳ deploy | **Fixed:** feeds were cache-first forever (never refreshed); Explore error state was dead code (now inline + Retry + pull-to-refresh); Search had no pull-to-refresh; semantic results went stale across queries; "Other" category never matched nil. Edge functions **hardened** (see §5) but not deployed. `view_count` = unique AR explorers via an `asset_views` insert trigger in the migration (plus backfill), not live until applied. Gaps: full-text search is client-side; no comments; `AssetDetailViewModel` is dead code. |
| WS6 E2E chat | ✅ core, ⏳ identity binding | **Fixed:** send silently fell back to **plaintext** when the peer had no key (now refused with a banner, text restored); notification quick-reply sent under the **peer's name** and bypassed encryption; in-app banner could show base64; ciphertext showed as noise before the key resolved; chat listener leaked (strong `self`); key only published on session restore (now on every sign-in/sign-up). **Fixed:** any Keychain read error (e.g. device locked before first unlock) silently minted a new identity key, orphaning every conversation. Now only `errSecItemNotFound` creates one; other errors throw and key publishing is skipped. The notification service extension replaces ciphertext bodies with "🔒 New encrypted message". Logout signs out of Firebase and login signs back in (`ContentView` follows `isAuthenticated`), and logout clears local state even when the server sign-out fails (e.g. right after account deletion). Still open: Firebase auth is anonymous → `senderId` spoofable, `firestore.rules` not deployable. |
| WS7 hand-draw | ✅ rebuilt, ⏳ device test | Previous export **could not work**: ModelIO can't write `.usdz` on iOS. **Fixed:** SceneKit export with per-stroke PBR colour, tube winding faced inward, no end caps, drawn file deleted itself before upload, Vision→screen mapping ignored `displayTransform`, Vision ran on the main thread, stroke never ended when the hand left frame, no point cap, geometry not recentred. Added width picker + canvas meter. |
| WS8 perf | ✅ with fix | **Fixed:** `MediaCache.localURL` never hit for files stored with an extension (every model re-downloaded). The 40-entity cap is per placement pass, not scene total. |
| WS9 release | ⏳ | Permission strings present (+ photo-library-add for snapshots). Invalid `Location` background mode removed. Safety/RLS migration written, **not applied** (§5). |

## 3. Added in stage 5 (verification pass)

- **Trust & safety** — `SafetyService` (block/unblock, report, hide reported, delete account), `ReportSheet`, "…" menus on `AssetDetailSheet` (Share / Report / Block) and `CreatorProfileView` (Report / Block / Unblock + blocked state). Blocked creators vanish from Explore, Search, Nearby, profiles, deep links and the AR scene. Local-first, server-synced once the migration lands.
- **Settings** (`ARSettingsView`, gear in Creator Studio): account + email (from the auth session), blocked creators with Unblock, **chat safety code** (key fingerprint), replay onboarding, clear model cache (shows size), sign out, **delete account** (App Store 5.1.1(v)).
- **AR Snapshot** — shutter in the viewer; `ARView.snapshot` → branded watermark (`ARSnapshotRenderer`) → preview with Save / Share.
- **Hot/cold finder** — chip pointing at the nearest *unfound* asset with distance + Warmer/Colder, haptic heartbeat that speeds up within 60 m, "You found it!" at ≤12 m (`ARDisplayViewModel+Finder.swift`, `DiscoveryStore`).
- **Explorer Passport** — XP, 6 levels, 9 badges, activity streak in Creator Studio (`ExplorerPassport.swift`), derived from finds, `asset_views.seen_at`, creations and hype.
- **Cold-launch deep links** — `DeepLinkRouter` catches `locolo://asset/<id>` at `ContentView` and hands it over after sign-in (previously dropped if the app launched to splash/login).
- **Offers** — owner's "View Offers" now passes `ownerId` (Accept/Reject were hidden); `DigitalAssetRepository.updateOfferStatus` filtered on non-existent `offers.id` (verified in prod) → `offer_id`.
- **Wishlist** — `WishlistView` used a private view model (stale vs. detail-sheet hearts) and `addToWishlist` never updated the list.
- **Email privacy (client side)** — no client query selects `users.email` any more (`User.publicColumns`); profile updates send only editable columns with `returning: .minimal`; signup sends username metadata for a server trigger.

- **Visibility filters** — Collection/Wishlist filtered `visibility` against Normal/Rare/Legendary, but creation writes `public`/`friends`/`private` (legacy prod rows say `normal`), so every filter but "All" was empty. Collection now filters by visibility (`DigitalAsset.normalizedVisibility`, `normal` → public); Wishlist filters by For sale / Offers and hides blocked/reported items. The migration's `da_select` now enforces private/friends server-side (it was `USING (true)`). **SECURITY DEFINER RPCs such as `get_nearby_assets` bypass RLS and must apply the same predicate.**

## 4. Critical invariants (break these = break the app)

1. **`DigitalAsset` ↔ RPC lockstep.** `get_nearby_assets_full`, `get_recommended_assets` and `get_asset_full` return the SAME 41 columns that `DigitalAsset.CodingKeys` decodes. New Swift fields must be optional.
2. **Memberwise-init call sites.** Adding a `DigitalAsset` field breaks `DigitalAssetRepository.swift` (~247) and `CacheMapper.swift` (~489).
3. **North-aligned frames.** Capture, draw and replay all use `.gravityAndHeading` / ENU.
4. **E2E means server-blind.** Never store plaintext server-side, never fall back to plaintext on send. Chat search stays on-device.
5. **`users.email` is private.** Never `select *` / `.select()` on `users` — use `User.publicColumns`. Updates on `users` must pass `returning: .minimal` (supabase-swift `update`/`upsert` default to `.representation`, which needs SELECT on every column). Profile updates send only `username, name, bio, avatar_url, cover_url`.
6. **Shared ARView.** `SharedARViewHolder.shared` outlives view models: track "did I start a session" per view model (`hasStartedSession`), clear anchors on reset, and drop late loads via `placementGeneration`.
7. **Filter UGC through `SafetyService`** on every new asset surface (`visible(_:)` / `isHidden(_:)`).
8. **Permission strings** live as `INFOPLIST_KEY_*` in `project.pbxproj`; `Info.plist` merges on top.
9. **Simulator-guard all AR code.** AR/Vision are device-only.

## 5. Remaining work (needs owner)

| Item | What's needed | Where |
|---|---|---|
| 🔴 **Apply safety & hardening migration** | Anyone with the app's anon key can currently read **every user's email**, and hype as any user. Ship the stage-5 app build first (older builds `select *` on users), then run the file in the SQL editor. It also creates `user_blocks`, `content_reports`, `delete_my_account`, `email_registered`, the `handle_new_user` signup trigger, revokes `run_sql`, and fixes `ar_model` categories. Supersedes `2026_ar_release_rls.sql`. | `docs/migrations/2026_ar_safety_and_hardening.sql` |
| Deploy edge functions | Set `OPENAI_API_KEY` + `EMBED_WEBHOOK_SECRET`, deploy all three, add the webhook header, backfill 10 assets. Functions now require a signed-in user (previously: `update-taste` let anyone rewrite anyone's taste vector with the service role, `embed-query` was an open OpenAI proxy, `embed-asset` re-triggered itself on its own UPDATE). | `supabase/functions/README.md` |
| Moderation process | Reports land in `content_reports` (service-role only). Someone must review the `status='open'` queue — App Store 1.2 expects timely action. | Supabase dashboard |
| Chat identity binding | Mint a Firebase custom token from the Supabase session (or move chat to Supabase Realtime + RLS), then deploy `firestore.rules`. Until then `senderId` is spoofable. | `firestore.rules` header |
| Commit the repo's missing RPCs | `get_asset_full` exists only in prod. | `pg_get_functiondef` |
| On-device field testing | Rotation replay, viewer re-entry, geo→world fallback, hand-draw pinch mapping + export, finder distances/haptics, snapshot save, deep link cold launch. | physical iPhone, outdoors |
| Storage cleanup on account deletion | `delete_my_account` removes rows + auth user, not uploaded files. Add a scheduled job. | Supabase |
| Push to GitHub | `git push github fresh-start:main`. **Never push to `origin` (Monash GitLab)** — unrelated 97-commit history, force-push would destroy it. | — |

Smaller known gaps: comments; `AssetDetailViewModel` dead code; background-location mode may draw App Review questions for an AR-only app. After applying the migration, smoke-test Explore and a deep link: section 4c flips `get_recommended_assets` / `get_asset_full` to `SECURITY INVOKER` if they were definer-mode (their source isn't in the repo).

## 6. Environment gotchas

- **CLI build**: `xcodebuild -project Locolo.xcodeproj -scheme Locolo -destination 'platform=iOS Simulator,id=FF468E8B-980D-4D49-AB78-785983B6C899' build` from `locolo/`.
- **Disk is ~99% full** (≈3 GB free). Incremental builds fit; a clean build may not — purge other DerivedData first.
- **SourceKit single-file diagnostics** show phantom errors — trust `xcodebuild`.
- Supabase project `zvrrbtiqsyzkyixbsybf`. Prod has real data (10 assets, 9 users) — treat migrations as production changes.
- `SupabaseManager.currentUserId` is a lowercased-UUID **String**; chat ids are lowercased UUID strings.
- `UserViewModel.logout()` wipes **all** UserDefaults (onboarding flag, local blocks, discoveries, key pins).

## 7. Changelog (newest first)

- **2026-09-27 (stage 5b, uncommitted):** audit follow-ups. Chat routes through the dashboard stack (`ARChatScreen`); visibility filters and server-side visibility RLS; Keychain-safe identity key; notification-extension ciphertext guard; Firebase session follows Supabase login; robust logout; `view_count` trigger; profile placement map; Geo ⇄ GPS toggle; GPS-mode re-anchoring; hype in-flight guard; follow-list error + Retry; removed the no-op "Also make this a post" toggle (visibility footer instead); removed `AppDelegate`'s plaintext reply path.

- **2026-09-27 (stage 5, uncommitted):** verification pass against code + prod. Fixed viewer lifecycle, radians/degrees, media cache, hand-draw export pipeline, feed refresh, chat plaintext fallback/quick-reply/listener leak, offers, wishlist, deep-link cold launch, `.create` owner fallback, Info.plist. Added safety (report/block/settings/delete account), snapshots, hot/cold finder, Explorer Passport, email-private data layer, hardened edge functions, safety & hardening migration.
- **2026-09-27 (stage 4, uncommitted):** ciphertext-notification fix, `locolo://asset/<id>` deep links + `get_asset_full`, post-save share, taste-vector wiring, first-launch onboarding.
- **2026-09-27 (stage 3):** de-stubbed AssetDetailSheet, profile messaging, key-change banner, chat restyle + search, semantic search rail, AR radar, category fix, `toggle_asset_hype`. Commit `9938d2f`.
- **2026-09-27 (stage 2):** WS0/2/3/4/8, WS5 code, WS6 core, WS7, UI polish, Mapbox removal. Commit `329cf3c`.
- **2026-09-27 (stage 1):** WS1 DB migration applied to prod; `get_recommended_assets` added.
