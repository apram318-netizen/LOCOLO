# LOCOLO AR — Project Status, Handoff & Runbooks

> **Audience:** AI coding agents and humans picking up this codebase.
> **Companion to:** `docs/LOCOLO_AR_RELEASE_SPEC.md` (the WS0–WS9 spec — read it for intent; read THIS for what actually exists and how to finish it).
> **Last updated:** 2026-09-27 · branch `fresh-start` · simulator build green via `xcodebuild`.
> **Git state:** all work through stage 5b is committed as `0393ca9` and pushed to **`github/fresh-start`**. GitHub `main` (`447c938`) is a direct ancestor, so merging is a fast-forward (§5.2). **Stage 6 (social network layer, §4.8) is uncommitted** on `fresh-start`.

---

## Contents

1. [Product in one paragraph](#1-product-in-one-paragraph)
2. [Quick start](#2-quick-start)
3. [Workstream status](#3-workstream-status)
4. [Everything that has been done](#4-everything-that-has-been-done)
5. [Instructions / runbooks](#5-instructions--runbooks)
6. [Critical invariants](#6-critical-invariants-break-these--break-the-app)
7. [Remaining work & known gaps](#7-remaining-work--known-gaps)
8. [Environment gotchas](#8-environment-gotchas)
9. [Changelog](#9-changelog-newest-first)

---

## 1. Product in one paragraph

Locolo is a **standalone AR-only social app** ("Instagram for real life"). After sign-in the app boots straight into `ARDashboardRootView` (Explore / Nearby / Search / Creator Studio). Users place USDZ models — or **draw them in the air** with a pinch — at real GPS coordinates. Others discover them in an AR viewer with a **radar**, a **hot/cold finder**, **snapshots** and a **Geo ⇄ GPS mode switch**, earn an **Explorer Passport**, follow creators, hype and wishlist assets, make offers, get a server-ranked **For You** feed with semantic search, and chat with **end-to-end encryption**. Report/block, settings, sign-out and in-app account deletion exist. Legacy non-AR screens remain in the repo but are off the boot path.

## 2. Quick start

| What | How |
|---|---|
| Repo root | `/Users/apps/Desktop/LOCOLO/locolo` (Xcode project `Locolo.xcodeproj`, scheme `Locolo`, iOS 17+) |
| Secrets | `Locolo/Secrets.swift` (gitignored) holds the Supabase URL + anon key. Required to build. |
| Build (CLI) | `xcodebuild -project Locolo.xcodeproj -scheme Locolo -destination 'platform=iOS Simulator,id=FF468E8B-980D-4D49-AB78-785983B6C899' build` |
| Run AR | **Physical iPhone only** (ARKit/Vision are simulator-guarded). Geo-anchoring needs a supported city; otherwise the app uses GPS mode. |
| New files | Filesystem-synced groups — new `.swift` files compile automatically, no pbxproj edit needed. |
| Backend | Supabase project `zvrrbtiqsyzkyixbsybf` (Postgres + PostGIS + pgvector). Chat on Firebase Firestore. |
| Git remotes | `github` = `github.com/apram318-netizen/LOCOLO` (**push here**). `origin` = Monash GitLab — **never push** (unrelated 97-commit history). |

Key code map:

| Area | Files |
|---|---|
| Boot / auth | `ContentView.swift`, `ARModule/ARAppRootView.swift`, `ViewModels/UsersViewModel.swift` |
| Dashboard + routing | `ARModule/ARDashboardRootView.swift`, `ARDashboardState.swift` (`ARRoute`) |
| AR viewer | `ARModule/Viewer/ARDisplayView(Model).swift`, `+Finder.swift`, `ARSnapshotRenderer.swift`, `Triggers/` |
| Creation / draw | `ARModule/Creation/*`, `ARModule/Draw/*` |
| Discovery | `ARModule/Dashboard/ARExploreView`, `ARSearchView`, `ARNearbyView`, `AssetDetailSheet`, view models in `ARModule/ViewModels/` |
| Social | `CreatorProfileView(Model)`, `FollowListView`, `Services/FollowRepository.swift` |
| Social stores (stage 6) | `Services/{EngagementStore,FollowStore,InboxStore,ActivityStore,CreatorCache,SocialSession,CommentsRepository,PeopleSearch}.swift` |
| Social UI (stage 6) | `ARSocialComponents.swift`, `Dashboard/{CommentsSheet,ARActivityView,AREditProfileView,ARMessagesView,ARSocialAssetCard}.swift`, `ARTabBar.swift` |
| Chat (E2E) | `Services/CryptoService.swift`, `Services/KeyDirectory.swift`, `ViewModels/ChatViewModel.swift`, `Views/Messages/ChatView.swift`, `Dashboard/ARChatScreen.swift`, `ARMessagesView.swift` |
| Safety / account | `Services/SafetyService.swift`, `Dashboard/ReportSheet.swift`, `Dashboard/ARSettingsView.swift` |
| SQL | `docs/migrations/2026_ar_release.sql` (applied), `2026_ar_safety_and_hardening.sql` (**not applied**), `2026_ar_social.sql` (**not applied**, run after safety) |
| Edge functions | `supabase/functions/{embed-asset,update-taste,embed-query,_shared}` + `README.md` |

## 3. Workstream status

"Verified" = code read and/or prod probed read-only with the anon key.

| WS | Status | Summary |
|---|---|---|
| WS0 boot AR-only | ✅ | `ContentView` → `ARAppRootView` → `ARDashboardRootView(isRootExperience: true)`. |
| WS1 DB migration | ✅ applied | `get_nearby_assets_full` (41 cols), `get_recommended_assets`, `get_asset_full`, `get_follow_counts`, `toggle_asset_hype` live in prod. `get_recommended_assets` + `get_asset_full` source is **not in the repo** (§5.5). Prod: 10 assets / 9 users. |
| WS2 rotation | ✅ code · ⏳ device | Quaternion-first replay; legacy Euler rows read as radians. |
| WS3 viewer resilience | ✅ code · ⏳ device | Re-entry, interruptions, fallbacks, retries, Geo ⇄ GPS switch, GPS re-anchoring (§4.1). |
| WS4 social | ✅ | Profiles, follow, map of placements, chat routing (§4.4). |
| WS5 discovery | ✅ code · ⏳ deploy | Feeds refresh, error states, semantic search wired; edge functions hardened but **not deployed** (§5.4). |
| WS6 E2E chat | ✅ core · ⏳ identity binding | No plaintext paths left; Firebase auth still anonymous (§5.8). |
| WS7 hand-draw | ✅ rebuilt · ⏳ device | SceneKit USDZ export, per-stroke colour, widths (§4.2). |
| WS8 perf | ✅ | Media cache fixed, download coalescing, 40-entity cap per pass. |
| WS9 release | ⏳ | Permission strings done; safety migration written but **not applied** (§5.3); store checklist §5.9. |

## 4. Everything that has been done

### 4.1 AR viewer (`ARDisplayViewModel`)
- **Shared ARView lifecycle fixed.** The viewer never restarted on a second visit (`session.configuration` stayed non-nil on the singleton). Now tracked per view model (`hasStartedSession`); anchors cleared on every reset (`clearPlacedContent`); late model loads dropped via `placementGeneration`.
- Ghost/duplicate anchors on re-entry and on geo→world fallback removed; geo interruptions now re-localize and re-place.
- `automaticallyConfigureSession = false` on viewer + placement views (it raced our north-aligned configs).
- Heading updates start on first permission grant (radar was blank on first launch).
- First-fetch failure retried every 20 s (previously never re-fetched).
- Legacy Euler rotations in prod are **radians** — they were read as degrees.
- **Geo ⇄ GPS switch** — the mode badge is tappable wherever ARKit reports geo data; remembered in `UserDefaults` `ar.prefersGPSMode`; usable while geo is still localizing (orange dot) instead of waiting for the 25 s auto-fallback.
- **GPS-mode re-anchoring** — on every 75 m walk refetch (fix ≤ 25 m accuracy) the world origin is re-based at the camera's current position; placed anchors are moved, out-of-range ones dropped. Previously everything was measured from the session-start fix and drifted.
- **Hot/cold finder** — chip for the nearest unfound asset with distance + Warmer/Colder, haptic heartbeat within 60 m, "You found it!" at ≤ 12 m (`+Finder.swift`, `DiscoveryStore`).
- **AR Snapshot** — shutter → `ARView.snapshot` → branded watermark → Save / Share.
- AR **radar** with correct bearing math; blocked/reported content never enters the scene.
- `MediaCache` hit fix (files stored with an extension never matched → every model re-downloaded); concurrent downloads coalesced.

### 4.2 Creation & hand-draw
- Placement captures world quaternion + scale under `.gravityAndHeading`, compass-accuracy gate (≤ 20°).
- `.create` no longer falls back to a random `UUID()` owner.
- **Hand-draw rebuilt:** ModelIO can't write `.usdz` on iOS → SceneKit export with per-stroke PBR colour; tube winding fixed; drawn file no longer deletes itself before upload; Vision→screen mapping uses `displayTransform`; Vision off the main thread; stroke ends when the hand leaves frame; point cap; geometry recentred; width picker + canvas meter.
- Post-save share (`locolo://asset/<id>`).
- Removed the no-op "Also make this a post" toggle; the Privacy picker now explains each visibility level.

### 4.3 Discovery
- Feeds were cache-first forever → now network-first with cache fallback; pull-to-refresh on Explore and Search.
- Explore error state (was dead code) → inline error + Retry.
- For You = `get_recommended_assets` with newest-first fallback; semantic search rail via `embed-query`; stale semantic results cleared per query; "Other" category matches nil.
- Legacy category `ar_model` normalised to `3d` everywhere (`DigitalAsset.normalizedCategory`).
- **Visibility filters** — Collection/Wishlist compared `visibility` against Normal/Rare/Legendary, but creation writes `public`/`friends`/`private` (legacy rows `normal`) → every filter but "All" was empty. Collection now filters by visibility (`normalizedVisibility`, `normal` → public); Wishlist filters For sale / Offers and hides blocked/reported items.
- `AssetDetailSheet`: hype (optimistic, one request in flight), wishlist, Open in AR (≤ 150 m), Share / Report / Block menu, offers.
- **Offers:** owner "View Offers" passes `ownerId` (Accept/Reject were hidden); `updateOfferStatus` used non-existent `offers.id` → `offer_id`.
- **Wishlist:** single shared view model (hearts were stale); `addToWishlist` updates the list.
- `view_count` = unique AR explorers via an `asset_views` insert trigger (in the unapplied migration, with backfill).

### 4.4 Social
- Creator profiles: header, follow/unfollow (optimistic + rollback), message, error banner + Retry.
- **"On the Map"** card — pins from `digital_assets → locations(latitude, longitude)`; tap opens the asset.
- "Assets" stat scrolls to the grid; private/friends assets hidden client-side to mirror server RLS.
- Follow list shows an error + Retry instead of "No followers yet" on failure.
- **Chat routing:** `ARMessagesView` nested a `NavigationStack` inside a pushed route → chats push `ARRoute.chat` via `ARChatScreen`, which owns its `ChatViewModel` (inline construction re-created the Firestore listener every render).

### 4.5 End-to-end encrypted chat
- X25519 identity key in the Keychain → HKDF-SHA256 (salt = conversation id) → AES-GCM.
- **No plaintext paths:** send refuses (banner, text restored) when the peer has no key; notification quick-reply encrypts and uses the right sender; `AppDelegate`'s raw reply path removed; in-app banner and the **notification service extension** show "🔒 New encrypted message" instead of ciphertext.
- Key published on every sign-in/sign-up (was only on session restore).
- **Keychain safety:** only `errSecItemNotFound` mints a new identity key; other Keychain errors throw (previously a locked device silently rotated the key and orphaned every conversation).
- Chat safety code (key fingerprint) in Settings; key-change banner in chat.
- Listener leak fixed (weak self); ciphertext no longer flashes before the key resolves.
- Firebase session follows Supabase login (sign out on logout, sign in on login).

### 4.6 Trust, safety & account
- `SafetyService`: block/unblock, report, hide reported, delete account. `ReportSheet`; "…" menus on asset sheet and profiles. Blocked creators vanish from Explore, Search, Nearby, profiles, deep links and the AR scene. Local-first, server-synced once the migration lands.
- **Settings** (gear in Creator Studio): account/email, blocked creators, chat safety code, replay onboarding, clear model cache, sign out, **delete account**.
- Logout always clears local state, even if the server call fails (e.g. right after deletion).
- First-launch onboarding; cold-launch deep links queued through `DeepLinkRouter` until sign-in.

### 4.7 Data & security (server side, written)
- Client never selects `users.email` (`User.publicColumns`); `users` updates send editable columns only with `returning: .minimal`.
- **`2026_ar_safety_and_hardening.sql`** (idempotent, one transaction): RLS on `users` with email column hidden; owner-only writes; `email_registered()`; `handle_new_user` signup trigger; `run_sql`/`exec_sql` revoked; AR-table policies incl. **visibility-enforcing `da_select`** (own / public / friends-you-follow); offers seller/buyer policies; `toggle_asset_hype` bound to `auth.uid()`; `view_count` trigger + backfill; read RPCs forced to `SECURITY INVOKER`; `user_blocks`, `content_reports`; `delete_my_account()`; authenticated-only baseline for legacy tables; `ar_model` → `3d`.
- **Edge functions hardened:** all require a signed-in user (`_shared/auth.ts`). Previously `update-taste` let anyone rewrite anyone's taste vector with the service role, `embed-query` was an open OpenAI proxy, `embed-asset` re-triggered itself on its own UPDATE.
- `Info.plist`: invalid `Location` background mode removed; photo-library-add string for snapshots.

### 4.8 Social network layer (stage 6, uncommitted)
Scope rule: stage 6 touches **only `ARModule/` and `docs/`**. No legacy screens, shared models/repositories, `ContentView` or `UsersViewModel` were changed.

- **Shared stores** (all `@MainActor` singletons, started by `SocialSession.start(me:)` from `ARAppRootView.onSignedIn`, torn down on `ARAppRootView.onDisappear`, i.e. sign-out):
  - `EngagementStore`: hyped set, hype counts, comment counts. It loads these in batches for whatever is on screen (one `asset_hype` query plus one `get_comment_counts` call) and toggles hype optimistically. Feed card, detail sheet and profile grid all read from it, so they never disagree. `commentsAvailable` flips false if the social migration isn't applied, and comment UI hides itself.
  - `FollowStore`: your following set. Every Follow button (`ARFollowButton`) and the Following feed use it. `CreatorProfileViewModel` routes through it and syncs its follower count.
  - `InboxStore`: live Firestore conversation list, peers, unread count. Unread means the thread changed after you last had it open. `ARChatScreen` calls `didOpen`/`didClose`, and threads first seen on a device start as read. Read state is local (`ar.inbox.lastRead`); nothing is sent to the peer and the chat data model is unchanged.
  - `ActivityStore`: follows, hypes, comments and offers on your assets, aggregated client-side from existing tables. Unread means newer than `ar.activity.lastSeen`, which is set when you leave the Activity screen.
  - `CreatorCache`: one batch-loaded `ARCreator` cache for every surface.
- **Comments:** `CommentsSheet` (resizable) offers a threaded list, a composer with quick emoji reactions, reply-by-mention, a "Creator" tag on the author's own comments, swipe/long-press Delete (own comment or your asset) and Report (reason picker via `SafetyService.reportComment`, with instant local hide), plus Block. Blocked users are filtered out. It degrades to "Comments are coming soon" before the migration.
- **Feed card:** creator row with inline Follow, relative time and place, and a "…" menu (share, copy link, report). 4:3 media with **double-tap to hype** and a burst animation. Action row: hype with live count, comments with count, share (deep link; this used to share the raw file URL), View in AR (≤ 150 m), and save (bookmark). Caption shows "View all N comments" and explorer count.
- **Detail sheet:** creator row (avatar, verified badge, @handle, Follow). Hype, comment and view capsules plus share. Comments open over the sheet. New `onOpenProfile` lets comment authors open their profiles.
- **Explore:** header has the AR viewer, **Activity bell** and **Messages** with unread badges. Skeleton loading, a **Creators to follow** rail (ranked by hype and output, excluding people you follow) and a **Following** filter with its own empty states. Pull to refresh reloads feed, follows and activity. The featured card now shows real hype, not views plus hype.
- **Tab bar:** raised gradient **Create** button in the centre. The Create "+" was removed from headers.
- **Activity screen** (`ARRoute.activity`): New / Earlier sections, filter chips (All, Follows, Hypes, Comments, Offers), kind badges on avatars, **Follow back**, and asset thumbnails that open the detail sheet.
- **Messages** (`ARMessagesView`, rebuilt on `InboxStore`): avatars with an unread ring and dot, verified badges, relative times, search, swipe to delete or mark read, long-press → View profile, a "Messages are end-to-end encrypted" footer, and a composer (`ARNewMessageSheet`: people you follow, then live search).
- **Profiles:** cover banner, gradient-ring avatar, @handle, join date, compact counts. Actions: Follow, Message (pushes chat on the dashboard stack) and **Share profile**. Your own profile shows **Edit profile** instead. The asset grid shows hype counts.
- **Creator Studio header:** cover, avatar, bio (or an "Add a bio" prompt), Creations/Followers/Following stats (tappable), Edit profile, Share profile, View as public. The Activity bell replaces the "+".
- **Edit profile** (`ARRoute.editProfile`, `AREditProfileView`): cover and avatar upload (compressed), display name (40), username (3–30 chars from `[a-z0-9._]` with a live availability check) and bio (150). Saves via `userVM.updateProfile`; a unique-violation shows "That username is taken".
- **Search:** a **Creators** rail (username/name `ilike`, ranked exact handle → prefix → verified) with Follow buttons, above asset results.
- **Deep links:** `locolo://user/<id>` (also `/profile/<id>`) → `DeepLinkRouter.pendingUserId`, consumed by `ARDashboardRootView`. Your own id switches to the Profile tab. Share sheets use `DeepLinkRouter.userURL(for:)`.

## 5. Instructions / runbooks

### 5.1 Build & run
1. Ensure `Locolo/Secrets.swift` exists (copy from a teammate; never commit it).
2. Simulator: run the build command in §2 from the repo root. SourceKit may show phantom single-file errors — trust `xcodebuild`.
3. Device: open `Locolo.xcodeproj`, select your team under Signing, run on an iPhone (A12+; LiDAR not required).
4. Disk is nearly full — if a clean build fails, delete other projects' DerivedData first.

### 5.2 Git: publish / merge
- Work on `fresh-start`; push with `git push github fresh-start` (upstream already set).
- To update GitHub `main` (fast-forward, no force): `git push github fresh-start:main` — or open a PR: <https://github.com/apram318-netizen/LOCOLO/pull/new/fresh-start>.
- **Never** `git push origin` and never force-push.
- Don't commit `xcuserdata/` files or `Secrets.swift`.

### 5.3 🔴 Apply the safety & hardening migration (highest priority)
Until this runs, **anyone with the anon key can read every user's email and hype as anyone**, and private/friends assets are readable by all.

1. **Ship the current app build first** (TestFlight / all testers updated). Older builds `select *` on `users` and will fail to load profiles once `email` is hidden.
2. Supabase dashboard → SQL Editor → paste `docs/migrations/2026_ar_safety_and_hardening.sql` → Run. It's one transaction and idempotent (safe to re-run). Watch the output for `Switched … to SECURITY INVOKER` notices.
3. Verify (anon key, from the repo root):
   ```bash
   KEY=$(rg -o 'eyJ[A-Za-z0-9._-]+' Locolo/Secrets.swift | head -1)
   curl -s "https://zvrrbtiqsyzkyixbsybf.supabase.co/rest/v1/users?select=email&limit=1" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY"      # expect permission denied / []
   ```
4. In the app (signed in): profiles load; Explore For You loads; a `locolo://asset/<id>` link opens; hype toggles; block/report work; Settings → Delete account works on a throwaway account.
5. Emergency rollback is at the bottom of the SQL file.
6. `2026_ar_release_rls.sql` is **superseded** — do not run it.

### 5.3b Apply the social migration (after §5.3)
`docs/migrations/2026_ar_social.sql` adds `asset_comments` with RLS. You can read comments only on assets you can see, post only as yourself, not post on a creator who blocked you, and delete your own comments or any on your asset. It also adds the `get_comment_counts(uuid[])` RPC (invoker) and `content_reports.comment_id`. It is idempotent and depends on `user_blocks` / `content_reports` from §5.3.
1. SQL Editor → paste → Run.
2. Verify: `curl -s "https://zvrrbtiqsyzkyixbsybf.supabase.co/rest/v1/asset_comments?select=comment_id&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY"` should return `[]` or permission denied, **not** a "relation does not exist" error.
3. In the app: the comment button appears on feed cards; post, delete and report a comment; counts update on card and detail sheet together.
4. Comment moderation: `select * from public.content_reports where comment_id is not null and status = 'open';` then `delete from public.asset_comments where comment_id = '<uuid>';`.

### 5.4 Deploy the edge functions
Full steps in `supabase/functions/README.md`. Summary:
```bash
supabase login && supabase link --project-ref zvrrbtiqsyzkyixbsybf
supabase secrets set OPENAI_API_KEY=sk-... EMBED_WEBHOOK_SECRET=$(openssl rand -hex 24)
supabase functions deploy embed-asset && supabase functions deploy update-taste && supabase functions deploy embed-query
```
Then create the `digital_assets` INSERT/UPDATE webhook → `embed-asset` with header `x-webhook-secret`, and backfill the existing assets:
```bash
curl -X POST "https://zvrrbtiqsyzkyixbsybf.supabase.co/functions/v1/embed-asset" \
  -H "x-webhook-secret: $SECRET" -H "Content-Type: application/json" \
  -d '{"type":"INSERT","record":{"asset_id":"<uuid>","name":"<name>","description":"<desc>"}}'
```
Until deployed, semantic search silently falls back to keyword search and For You to newest-first.

### 5.5 Commit the prod-only RPCs
In the SQL editor:
```sql
select pg_get_functiondef('public.get_recommended_assets'::regproc);
select pg_get_functiondef('public.get_asset_full'::regproc);
```
Save the output as `docs/migrations/2026_prod_rpcs_dump.sql` and commit. Both must keep returning the same 41 columns as `DigitalAsset` (§6.1).

### 5.6 Moderation (App Store 1.2)
Reports land in `content_reports` (service-role only). Review at least daily:
```sql
select report_id, reason, details, asset_id, reported_user_id, reporter_id, created_at
from public.content_reports where status = 'open' order by created_at;

-- take action (e.g. delete the asset), then close the report
delete from public.digital_assets where asset_id = '<uuid>';
update public.content_reports set status = 'actioned', reviewed_at = now() where report_id = '<uuid>';
-- or: set status = 'dismissed'
```

### 5.7 On-device test checklist (outdoors, physical iPhone)
- [ ] Place an asset; walk away and back; open the viewer twice in a row (re-entry works, no duplicates).
- [ ] Rotation of new and legacy assets matches what the creator placed.
- [ ] Geo city: badge shows Geo-anchored; tap → GPS mode and back; preference persists after relaunch.
- [ ] Non-geo area: GPS mode starts automatically; walk > 75 m and confirm assets stay put (re-anchoring).
- [ ] Background the app mid-session → returns and re-places.
- [ ] Hot/cold finder distances + haptics; "You found it!" at ≤ 12 m.
- [ ] Snapshot → Save to Photos (permission prompt) and Share.
- [ ] Hand-draw: pinch mapping follows fingertip; export + upload succeeds; colours and widths survive; drawing appears where placed.
- [ ] Chat between two devices: encrypted send/receive, notification shows 🔒 text, inline reply works, safety codes match.
- [ ] Cold-launch `locolo://asset/<id>` from Notes while signed out → opens after sign-in.
- [ ] Profile map pins open the right asset; private assets hidden on others' profiles.
- [ ] Delete account on a throwaway user → signed out, can't sign back in.
- [ ] Two accounts: A follows B → B's Activity bell badges, "Follow back" works; A's Following feed shows B's work.
- [ ] Double-tap a feed card → burst + hype; open the detail sheet → same hype state and count.
- [ ] Comment from A on B's asset → B sees it in Activity; B deletes it; A reports another → hidden for A.
- [ ] Message from A → B's Messages badge + unread dot; opening the thread clears it; own sends never show unread.
- [ ] Edit profile: change avatar/cover/username; a taken username is rejected; new name shows on cards.
- [ ] `locolo://user/<id>` opens the profile (cold launch too); Share profile produces that link.
- [ ] Sign out and in as another user → no stale follows, unread or activity.

### 5.8 Chat identity binding (before public launch)
Firebase auth is anonymous, so `senderId` is spoofable and `firestore.rules` can't be deployed (it would block all chat). Options:
- **(B, recommended)** Edge function that verifies the Supabase JWT and mints a Firebase custom token with `uid = Supabase user id`; replace `signInAnonymously()` in `ContentView.signInFirebaseIfNeeded()`; deploy `firestore.rules` (add a `delete` rule for full conversation deletes).
- **(A)** Move chat to Supabase Realtime + RLS.

### 5.9 App Store submission checklist
- [ ] Migration applied (§5.3) and edge functions deployed (§5.4).
- [ ] Moderation owner assigned (§5.6); support contact in the listing.
- [ ] Privacy policy URL covers location, camera, photos, chat (E2E), account deletion.
- [ ] Review notes: demo account, a geo-supported test location or note that GPS mode works anywhere.
- [ ] Reconsider the background-location mode — an AR-only app may get asked to justify it.
- [ ] Storage cleanup for deleted accounts (scheduled job; `delete_my_account` removes rows, not files).

## 6. Critical invariants (break these = break the app)

1. **`DigitalAsset` ↔ RPC lockstep.** `get_nearby_assets_full`, `get_recommended_assets` and `get_asset_full` return the SAME 41 columns that `DigitalAsset.CodingKeys` decodes. New Swift fields must be optional.
2. **Memberwise-init call sites.** Adding a `DigitalAsset` field breaks `DigitalAssetRepository.swift` (~247) and `CacheMapper.swift` (~489).
3. **North-aligned frames.** Capture, draw and replay all use `.gravityAndHeading` / ENU.
4. **E2E means server-blind.** Never store plaintext server-side, never fall back to plaintext, never write chat messages outside `ChatViewModel`'s encrypted send. Chat search stays on-device.
5. **`users.email` is private.** Never `select *` on `users` — use `User.publicColumns`. `users` updates pass `returning: .minimal` and only `username, name, bio, avatar_url, cover_url` (+ key columns).
6. **Shared ARView.** `SharedARViewHolder.shared` outlives view models: use `hasStartedSession`, clear anchors on reset, drop late loads via `placementGeneration`, and keep `worldAnchors` in sync with placed content.
7. **Filter UGC through `SafetyService`** (`visible(_:)` / `isHidden(_:)`) and respect `normalizedVisibility` on every new asset surface.
8. **Read RPCs stay `SECURITY INVOKER`** so `da_select` visibility applies; any new SECURITY DEFINER function must re-apply the visibility predicate.
9. **Permission strings** live as `INFOPLIST_KEY_*` in `project.pbxproj`; `Info.plist` merges on top.
10. **Simulator-guard all AR/Vision code.**
11. **Social state goes through the stores.** Hype via `EngagementStore.toggleHype`, follows via `FollowStore.toggle`/`ARFollowButton`, user rows via `CreatorCache`. Per-view copies drift. New stores must be reset in `SocialSession.end()`.

## 7. Remaining work & known gaps

| Priority | Item | Runbook |
|---|---|---|
| 🔴 | Apply safety & hardening migration | §5.3 |
| 🟠 | Apply social migration (comments) | §5.3b |
| 🟠 | Commit stage 6 | §5.2 |
| 🔴 | Chat identity binding (Firebase custom token) | §5.8 |
| 🟠 | Deploy edge functions + backfill embeddings | §5.4 |
| 🟠 | On-device field testing | §5.7 |
| 🟠 | Moderation process owner | §5.6 |
| 🟡 | Commit prod-only RPC source | §5.5 |
| 🟡 | Storage cleanup job for deleted accounts | §5.9 |
| 🟡 | Merge `fresh-start` → GitHub `main` | §5.2 |

Smaller gaps: no push notifications for follows/hypes/comments (activity is pull-based, refreshed on foreground and pull-to-refresh); inbox read state is per device; activity aggregation caps at the newest 300 of your assets; no comment likes/threads beyond @mentions; full-text search is client-side (DB `search_tsv` unused); `AssetDetailViewModel` is dead code; 40-entity cap is per placement pass, not a scene total; Collection lists your own creations (no purchase ownership model yet); key rotation makes old messages unreadable (no ratchet / forward secrecy); multiple devices per account = last device's key wins.

## 8. Environment gotchas

- Disk is ~99 % full (≈ 3 GB free). Incremental builds fit; clean builds may not.
- SourceKit single-file diagnostics show phantom errors — trust `xcodebuild`.
- Prod has real data (10 assets, 9 users) — treat every SQL change as a production change.
- `SupabaseManager.currentUserId` is a lowercased-UUID **String**; chat ids are lowercased UUID strings.
- `UserViewModel.logout()` wipes **all** UserDefaults (onboarding flag, local blocks, discoveries, key pins, `ar.prefersGPSMode`).
- supabase-swift `update`/`upsert` default to `returning: .representation` (needs SELECT on every column).
- `locations` has plain `latitude`/`longitude` columns alongside `geom`; embed them via `locations(latitude, longitude)`.
- The real table is `event_attendance` (not `event_attendees`).

## 9. Changelog (newest first)

- **2026-09-27 (stage 6) — uncommitted, AR module only:** social network layer (§4.8). Shared engagement/follow/inbox/activity stores; comments (UI + `2026_ar_social.sql`); redesigned feed card with double-tap hype; creator row + follow on the detail sheet; Explore Following filter, creator suggestions, skeletons and badged Activity/Messages; Activity screen; rebuilt Messages inbox with unread state; centre Create tab; profile cover/share/edit; AR Edit Profile; Search Creators rail; `locolo://user/<id>` deep links.

- **2026-09-27 (stage 5b) — `0393ca9`, pushed to `github/fresh-start`:** audit follow-ups. Chat via `ARChatScreen` on the dashboard stack; visibility filters + server-side visibility RLS; Keychain-safe identity key; notification-extension ciphertext guard; Firebase session follows Supabase login; robust logout; `view_count` trigger; profile placement map; Geo ⇄ GPS toggle; GPS-mode re-anchoring; hype in-flight guard; follow-list error + Retry; removed no-op post toggle; removed `AppDelegate` plaintext reply path.
- **2026-09-27 (stage 5) — in `0393ca9`:** verification pass against code + prod. Fixed viewer lifecycle, radians/degrees, media cache, hand-draw export pipeline, feed refresh, chat plaintext fallback/quick-reply/listener leak, offers, wishlist, deep-link cold launch, `.create` owner fallback, Info.plist. Added report/block/settings/delete account, snapshots, hot/cold finder, Explorer Passport, email-private data layer, hardened edge functions, safety & hardening migration.
- **2026-09-27 (stage 4) — in `0393ca9`:** ciphertext-notification fix, `locolo://asset/<id>` deep links + `get_asset_full`, post-save share, taste-vector wiring, first-launch onboarding.
- **2026-09-27 (stage 3) — `9938d2f`:** de-stubbed AssetDetailSheet, profile messaging, key-change banner, chat restyle + search, semantic search rail, AR radar, category fix, `toggle_asset_hype`.
- **2026-09-27 (stage 2) — `329cf3c`:** WS0/2/3/4/8, WS5 code, WS6 core, WS7, UI polish, Mapbox removal.
- **2026-09-27 (stage 1):** WS1 DB migration applied to prod; `get_recommended_assets` added.
