# LOCOLO AR — Project Status, Handoff & Runbooks

> **Audience:** AI coding agents and humans picking up this codebase.
> **Companion to:** `docs/LOCOLO_AR_RELEASE_SPEC.md` (the WS0–WS9 V1 spec — read it for intent; read THIS for what actually exists and how to finish it).
> **Next phase (design, not built):** `docs/LOCOLO_V2_ROADMAP.md` (umbrella) → `LOCOLO_V2_MARKETPLACE.md` (blockchain/trading/payments/portfolio graphs), `LOCOLO_V2_SOCIAL_AND_UI.md` (deeper social + Gen-Z design), `LOCOLO_V2_SECURITY.md` (security/compliance for money+keys). Start with the Roadmap's §3 decision table.
> **AR polish backlog:** `docs/LOCOLO_AR_POLISH.md` — prioritized enhancements to the *existing* AR module (spatial audio, video-as-texture, trigger effects, discovery reveal, occlusion, AR video capture, creation finesse).
> **🔴 Release:** see `docs/LOCOLO_RELEASE_CHECKLIST.md` (2026-10-03) — single source of truth for what's left before App Store submission.
> **Last updated:** 2026-09-28 · branch `fresh-start` · tip `626b940` (9 commits ahead of `github/fresh-start`).
> **Where work is:** V2 Phase A–D client coded in the working tree (uncommitted). Marketplace B/C foundations + Phase D social bulk. Real partner checkout / chain contracts still need edge fns + audits.
>
> **🟢 ALL SQL APPLIED — §5.10–§5.28 done (2026-09-28).** Every pending V2 migration is live in prod and verified (28 tables / 29 RPCs / 7 triggers / 65 RLS tables; no ERROR-level advisor findings). **⚠️ Four of the .sql files need fixes before they can be re-run verbatim — see §6b.** Full remaining plan: `LOCOLO_V2_COMPLETION_PLAN.md`.
> **🟢 V1 DB migrations APPLIED (2026-09-28):** safety/hardening, social/comments, notifications (step 1), flat-view RLS fix. Remaining work is **deploy/keys/device only**: §5.3c steps 2–6 (APNs + `send-push` + webhook + `push_enabled`), edge functions incl. `purge-storage` (§5.4 / §5.25), chat identity binding (§5.8), on-device QA (§5.7), contract audit + partner keys.
> **🟢 Client ship-ready (stage 19):** stage 18 polish + Phase B `onramp-session` client, post-trade asset refresh, Activity V2 filters, AR location usage strings, hot-path `LocoloLog`, §5.28 trigger CHECK SQL. **No further in-repo client work required for ship** — owner SQL/deploy/partners/QA remain.
> **🟢 V2 Phase A trading DB APPLIED:** `2026_v2_marketplace_phase_a.sql`. Mint/coupons/provenance: draft was live; **canonical fixed SQL is now in the repo** — re-apply §5.10.

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
| Notifications (stage 7) | `Services/{ARNotificationRouter,PushRegistry,NotificationPreferences,ProximityNotifier}.swift` (+ `BadgeSync`, `ARPushEvents` in the router file); hooks in `NotificationManager`, `AppDelegate`, `ChatViewModel.sendMessage` |
| Minting / authenticity (WIP) | `Services/{MintingService,CryptoService,KeyDirectory}.swift`, `Creation/{DetailsStepView,ARCreateViewModel}.swift` — see §4.10 |
| Chat (E2E) | `Services/CryptoService.swift`, `Services/KeyDirectory.swift`, `ViewModels/ChatViewModel.swift`, `Views/Messages/ChatView.swift`, `Dashboard/ARChatScreen.swift`, `ARMessagesView.swift` |
| Safety / account | `Services/SafetyService.swift`, `Dashboard/ReportSheet.swift`, `Dashboard/ARSettingsView.swift` |
| SQL (applied) | `2026_ar_release.sql`, `2026_ar_safety_and_hardening.sql`, `2026_ar_social.sql`, `2026_ar_notifications.sql`, `2026_ar_flat_view_rls.sql`, `2026_v2_marketplace_phase_a.sql` |
| SQL (missing from repo) | Coupons + mint-orders + provenance layer that is **live in prod** — must be dumped (§5.10 / §7) |
| Edge functions | `supabase/functions/{embed-asset,update-taste,embed-query,send-push,_shared}` + `README.md` |

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
| WS9 release | ⏳ | Permission strings done; V1 safety/social/notifications migrations **applied**; store checklist §5.9; push + edge fns still pending. |
| V2 Phase A marketplace | 🟡 code · ⏳ apply SQL | Trading DB applied. Client: `MarketplaceRepository` + `MarketplaceSheet` (list/buy/cancel) + portfolio chart + provenance timeline. Uncommitted. |
| V2 mint / coupons / provenance | 🟡 code · ⏳ apply SQL | Canonical SQL in repo (§5.10) fixes coupon bug + adds `attach_mint_order`. Swift mint paywall + Ed25519 authenticity build-green, uncommitted. |

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

### 4.8 Social network layer (stage 6, `9f73f48`)
Scope rule: stage 6 touches **only `ARModule/` and `docs/`**. No legacy screens, shared models/repositories, `ContentView` or `UsersViewModel` were changed.

- **Shared stores** (all `@MainActor` singletons, started by `SocialSession.start(me:)` from `ARAppRootView.onSignedIn`, torn down on `ARAppRootView.onDisappear`, i.e. sign-out):
  - `EngagementStore`: hyped set, hype counts, comment counts. It loads these in batches for whatever is on screen (one `asset_hype` query plus one `get_comment_counts` call) and toggles hype optimistically. Feed card, detail sheet and profile grid all read from it, so they never disagree. `commentsAvailable` flips false if the social migration isn't applied, and comment UI hides itself.
  - `FollowStore`: your following set. Every Follow button (`ARFollowButton`) and the Following feed use it. `CreatorProfileViewModel` routes through it and syncs its follower count.
  - `InboxStore`: live Firestore conversation list, peers, unread count. Unread means the thread changed after you last had it open. `ARChatScreen` calls `didOpen`/`didClose`, and threads first seen on a device start as read. Read state is cached locally (`ar.inbox.lastRead`) and, since stage 7, synced across your own devices (§4.9); nothing is sent to the peer and the chat data model is unchanged.
  - `ActivityStore`: the activity feed. Since stage 7 it reads the server `notifications` table (§4.9); before that migration it aggregates follows, hypes, comments and offers client-side, and unread means newer than `ar.activity.lastSeen` (set when you leave the Activity screen).
  - `CreatorCache`: one batch-loaded `ARCreator` cache for every surface.
  - `StoryStore` (Phase D): 24h story rail via `get_story_rail`; post + `mark_story_viewed`. Reset in `SocialSession.end()`. Hides the rail when §5.11 isn't applied.
  - `BoardsStore` (Phase D): curated boards via `get_user_boards` / `get_board_item_ids`. Reset in `SocialSession.end()`. Hides boards when §5.12 isn't applied.
  - Tier 2–3 (Phase D, §5.20): `ReactionStore`, `RemixStore`, `CollabStore`, `PollStore`, `PresenceStore`, `EventsStore`, `SafetyExtrasStore` — all configure/reset in `SocialSession`. Degrade when schema missing.
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

### 4.9 Notifications (stage 7, committed)
Scope: AR module + `docs/` + `supabase/`, plus four small, marked hooks in shared files (listed at the end).

**Events.** Every event becomes one row in `notifications`, written by database triggers (`2026_ar_notifications.sql`). The client never inserts them.

| Type | Trigger | Recipient | Push copy (`send-push`) |
|---|---|---|---|
| `follow` | `follows` insert, or status changes to accepted (unfollowing removes the unread row) | followee | "Maya · @maya — started following you." |
| `hype` | `asset_hype` insert (un-hype removes the unread row) | owner | "⚡ Maya hyped “Neon Koi”" |
| `comment` | `asset_comments` insert | owner | "Maya commented on “Neon Koi”" + the comment |
| `mention` | `@handle` in a comment (max 5; only people who can see the asset) | mentioned user | "Maya mentioned you on “Neon Koi”" |
| `offer` | `offers` insert | owner | "💰 New offer: $25.00" |
| `offer_status` | offer accepted or rejected | buyer | "🎉 Offer accepted" / "Offer declined" |
| `new_post` | `digital_assets` insert (public or friends visibility) | every follower | "✨ Maya dropped something new" |
| `discovery` | new unique explorer (`asset_views` insert; max 1 unread per asset per hour) | owner | "🧭 Sam discovered “Neon Koi”" |
| `milestone` | `hype_count` / `view_count` crosses 10, 25, 50, 100, 250… | owner | "🔥 “Neon Koi” hit 100 hypes" |
| `message` | `notify_message` RPC, called by `ChatViewModel.sendMessage` after a successful send | peer | "Maya — 🔒 New message" (never the body; E2E) |

`_notify()` is the only insert path. It skips self-notifications and actors the recipient has blocked, and drops a follow or hype repeated within 24 h. `notify_message` is rate-limited to 60 per sender per 10 minutes, and keeps one fresh unread row per conversation.

**Delivery.**
- **Remote push:** a Database Webhook on `notifications` INSERT calls `supabase/functions/send-push`.
  - It checks `notification_prefs`, composes the copy, sets the badge to the recipient's unread count, and sends to APNs over HTTP/2 with an ES256 JWT (no FCM).
  - It picks the sandbox or production host per token, and deletes tokens APNs rejects (410 / BadDeviceToken / Unregistered).
  - Grouping: `thread-id` per asset or conversation. Collapsing: `apns-collapse-id` per chat and per follower.
  - Categories: `CHAT_MESSAGE` (quick reply) or `SOCIAL`.
- **Local fallback:** until `app_config.push_enabled` is true (`PushRegistry.serverPushActive`), the app posts the same events as local notifications while it's running.
  - `ActivityStore` covers new activity: at most 3 individually, otherwise one summary. The first load on a device counts as backlog and doesn't alert.
  - `InboxStore` covers new messages in threads you don't have open: "🔒 New message", with quick reply.
  - Background location wakes refresh activity every ≤ 5 minutes (`SocialSession`). Once push is live, the fallbacks switch off, so nothing arrives twice.
- **Tokens:** `PushRegistry` registers through `register_device_token`, which reassigns a shared phone to whoever is signed in. It sends the environment (`#if DEBUG` → sandbox) and the bundle id. `ARSettingsView.signOut` unregisters the token before logout.

**Read state follows the account, not the device.**
- Activity: server `read_at`. Leaving the Activity screen marks everything read everywhere; swipe to clear deletes a row.
- Messages: `conversation_reads` rows (batched upserts every 1.5 s). They merge into the local cache on sign-in and on every foreground. A trigger marks that conversation's message notifications read, so the badge drops on every device.
- `BadgeSync` keeps the app-icon badge equal to activity unread plus conversations unread.

**Routing.** `NotificationManager` stays the delegate (it owns quick reply) and forwards to `ARNotificationRouter`.
- Taps open `userInfo.url` through `DeepLinkRouter`: `locolo://asset/…`, `locolo://user/…`, and the new `locolo://chat/<id>`, `locolo://activity`, `locolo://messages` and `locolo://viewer` routes (`pendingRoute`, consumed by `ARDashboardRootView`).
- Older chat notifications, which only carry `conversationId`, still open their thread.
- In the foreground, the banner is hidden for the chat you're reading, and social pushes refresh Activity immediately.

**Nearby AR art (`ProximityNotifier`).**
- Example: title "✨ “Neon Koi” is 43 m away", subtitle "AR art by @maya", body "43 m north-east of you near Federation Square · Sculpture. Open the AR camera to discover it. +2 more AR creations within 100 m."
  - It adds a thumbnail attachment and actions **View in AR** / **Details**.
  - It says "You've found this one before" when `DiscoveryStore` knows the asset.
- Rides `LocationManager.$userLocation` (no extra GPS session). Fetches `get_nearby_assets_full` within 1 km, again after moving 300 m or after 10 minutes.
- Alerts within **100 m** and re-arms only after you're more than 150 m away. Each asset waits 6 h; globally at most one alert per 3 minutes and 12 per day. The nearest asset wins.
- Skips your own assets, blocked creators, reported assets, and the open AR viewer.
- Geofences the 15 nearest candidates (needs Always location), so iOS relaunches the app for an alert even after termination. `AppDelegate` creates the notifier at launch for this.
- Uses the local preferences mirror, so it works on a background relaunch.

**Settings.** New Notifications section with toggles for new followers, hypes, comments, mentions, messages, offers, new from people you follow, discoveries & milestones, and AR art nearby. The toggles are stored server-side (`notification_prefs`, which `send-push` respects) and mirrored locally (for local and nearby alerts). It also shows a "Notifications are off" prompt with Open Settings when permission is denied, and a Turn on button when not yet asked.

**Shared-file hooks (outside `ARModule/`):**
- `NotificationManager`: registers the AR categories alongside `CHAT_MESSAGE`; forwards non-reply taps and foreground presentation to the router.
- `AppDelegate`: APNs token callbacks → `PushRegistry`; creates `ProximityNotifier` at launch.
- `ChatViewModel`: remembers the resolved peer and calls `ARPushEvents.messageSent` after a successful send.
- `Info.plist`: adds `remote-notification` to `UIBackgroundModes`.

### 4.10 Minting, coupons, authenticity & Phase A marketplace (uncommitted, build green)
**Intent:** every new AR creation is a paid mint (default **$2.99**) on an authenticity ledger. Coupon **`LOCOLO100`** = 100% off for QA. Device signs with Ed25519. Paid checkout is Phase B — until then only waived orders mint. Owners can list/sell off-chain; buyers call `buy_listing`; provenance + portfolio chart surface the history.

**SQL (in repo — apply to prod via §5.10):** `docs/migrations/2026_v2_mint_coupons_provenance.sql`
- Tables: `coupons` (`code`, `discount_type`, `discount_value`, `max_uses`, `used_count`, …), `mint_orders`, `provenance_records`
- Columns: `digital_assets.{content_hash,creator_signature,creator_signing_key,owner_id}`, `users.{ed25519_public_key,signing_key_updated_at}`
- RPCs: `preview_mint_fee` (**fixed** — no ambiguous `code`), `create_mint_order`, **`attach_mint_order(p_order, p_asset)`**
- Triggers: genesis `mint` provenance on asset insert; `sale` provenance on `trades` insert
- Seeds `LOCOLO100` percent/100. Locally verified: preview free, create waived, attach → consumed, provenance hash length 64.
- Trading foundation remains `2026_v2_marketplace_phase_a.sql` (`buy_listing` 7.5% / 2.5%).

**Client (working tree, `xcodebuild` green):**

| File | Role |
|---|---|
| `CryptoService` / `KeyDirectory` | Ed25519 signing identity + publish/fetch |
| `MintingService` | preview / create / **attach** |
| `ARCreateViewModel` + `DetailsStepView` | hash → sign → insert → attach order; mint paywall + coupon |
| `MarketplaceRepository` + `MarketplaceSheet` | list / cancel / buy now / provenance timeline |
| `AssetDetailSheet` | Marketplace entry; owner = `ownerId ?? userId` |
| `ARProfileViewModel` + Creator Studio | portfolio snapshots + value-over-time chart |
| `DigitalAsset.ownerId` | optional; RPCs don't return it yet (nil until `get_*` extended) |

**Still open:**
1. 🔴 **Apply §5.10 SQL in Supabase** (prod still has the broken `preview_mint_fee` until you do).
2. 🟠 Extend read RPCs with optional `owner_id` (and authenticity fields when the UI needs them).
3. ✅ Phase B paid mint client: intent + `onramp-session` checkout (partner URL when keys live).
4. ✅ Auctions / bids UI + live refresh of asset after buy/list/cancel.
5. 🟡 Commit + push (`fresh-start` already ahead of github).
6. 🟡 Partner edge deploy + contract audit still required. Phase D social coded — apply §5.11–§5.28.

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

### 5.3 ✅ Apply the safety & hardening migration — DONE 2026-09-28
Previously: anyone with the anon key could read every user's email and hype as anyone, and private/friends assets were readable by all. **Applied.** Keep the steps below for other environments / rollback.

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

### 5.3c Notifications: migration, push function, webhook, capability (after §5.3b)
The app works before any of this: Activity falls back to client aggregation, and alerts are local while the app runs. Each step below adds more.

1. **Migration.** SQL Editor → paste `docs/migrations/2026_ar_notifications.sql` → Run. It's idempotent and adds `notifications`, `notification_prefs`, `device_tokens`, `conversation_reads`, `app_config`, all the triggers, and the `register_device_token` / `unregister_device_token` / `notify_message` RPCs.
   - Check: in the app, follow a second account; that account's Activity shows the follow and its bell badges. Reading on one device clears it on the other.
2. **APNs key** (Apple Developer → Keys → + → Apple Push Notifications service). Download `AuthKey_XXXXXXXXXX.p8` once and note the Key ID and Team ID. The key must belong to the team that owns the bundle id you ship:
   - Debug: `com.apram.locolo`, team `RB24MJ38LB`.
   - Release: `edu.monash.Locolo`, team `MDUMW2CFXU`.
3. **Push capability.** Xcode → Locolo target → Signing & Capabilities → **+ Capability → Push Notifications**. This creates `Locolo.entitlements` with `aps-environment` and updates the App ID.
   - A free personal team can't use this capability, which is why it isn't committed.
   - Without it, token registration fails quietly and the app keeps using local fallbacks.
4. **Deploy:**
   ```bash
   supabase functions deploy send-push --no-verify-jwt
   supabase secrets set PUSH_WEBHOOK_SECRET=$(openssl rand -hex 24) \
     APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=XXXXXXXXXX \
     APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" APNS_BUNDLE_ID=com.apram.locolo
   ```
5. **Webhook.** Database → Webhooks → Create: table `notifications`, event **INSERT**, type Supabase Edge Function → `send-push`, HTTP header `x-webhook-secret: <PUSH_WEBHOOK_SECRET>`.
6. **Flip the flag** (this turns the app's local fallbacks off, so nothing arrives twice):
   ```sql
   update public.app_config set value = 'true' where key = 'push_enabled';
   ```
7. **Test:** on a device build, sign in, allow notifications, and check `select * from device_tokens;`. Then get followed or messaged from another account; the push arrives with the app closed. Function logs: Dashboard → Edge Functions → send-push → Logs.
8. **Optional:** nightly prune of read notifications older than 90 days: `select cron.schedule('prune-notifications', '17 3 * * *', 'select public.prune_notifications()');`.

Notes:
- `new_post` fans out one row per follower, and so one webhook call each. That's fine at current scale; batch it if a creator passes ~5k followers.
- The dormant `LocoloNotificationService` extension target is still a macOS target and isn't embedded. `send-push` doesn't set `mutable-content`, so it isn't needed.

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
- [ ] Walk toward someone's asset: an alert at ≤ 100 m shows the name, exact metres, direction, @creator and a thumbnail. **View in AR** opens the viewer and **Details** opens the asset. Standing still doesn't re-alert; walking > 150 m away and back after 6 h does.
- [ ] Kill the app (Always location on), walk to an asset → the nearby alert still arrives (geofence relaunch).
- [ ] No nearby alert for your own assets, blocked creators, or while the AR viewer is open. The Settings toggle off → silence.
- [ ] Before push is live: B follows / hypes / comments on / mentions A, or makes an offer, while A has the app in the background → A gets a local alert for each, and a summary if more than 3 arrive.
- [ ] After §5.3c: the same events arrive with the app killed. Tapping each opens the right screen (profile, asset, chat, Activity). The app badge equals the unread total.
- [ ] Message A → B while B is on another thread → banner. While B has that thread open → no banner. Quick reply from the banner sends encrypted.
- [ ] Read a thread on device 1 → it's no longer unread on device 2 after foregrounding. Activity read on one device → read on the other.
- [ ] Accept an offer → the buyer gets "Offer accepted". Publish a public asset → followers get "dropped something new". Hit 10 hypes → the owner gets a milestone.
- [ ] Sign out → `device_tokens` row removed; the next account on the phone gets only its own pushes.

### 5.8 Chat identity binding (before public launch)
Firebase auth is anonymous, so `senderId` is spoofable and `firestore.rules` can't be deployed (it would block all chat). Options:
- **(B, recommended)** Edge function that verifies the Supabase JWT and mints a Firebase custom token with `uid = Supabase user id`; replace `signInAnonymously()` in `ContentView.signInFirebaseIfNeeded()`; deploy `firestore.rules` (add a `delete` rule for full conversation deletes).
- **(A)** Move chat to Supabase Realtime + RLS.

**Client + stub (stage 18):** iOS already prefers `firebase-custom-token` then falls back to anonymous. Edge stub at `supabase/functions/firebase-custom-token` returns 503 until `FIREBASE_SERVICE_ACCOUNT_JSON` is set and Admin `createCustomToken` is wired. Owner: set secret + finish mint + deploy rules.

### 5.9 App Store submission checklist
- [x] V1 migrations applied (§5.3 / 5.3b / 5.3c step 1).
- [ ] Edge functions deployed (§5.4); push fully live (§5.3c steps 2–6).
- [ ] Moderation owner assigned (§5.6); support contact in the listing.
- [ ] Privacy policy URL covers location, camera, photos, chat (E2E), account deletion, and (once minting ships) paid minting / marketplace.
- [ ] Review notes: demo account, a geo-supported test location or note that GPS mode works anywhere; include test coupon `LOCOLO100` only for internal QA.
- [ ] Reconsider the background-location mode — an AR-only app may get asked to justify it.
- [ ] Storage cleanup for deleted accounts — **SQL + edge ready** (`2026_v2_storage_cleanup.sql` §5.27 + `purge-storage`); apply + schedule cron.
- [ ] Legal review of mint fee / marketplace framing before any paid path (V2 Security / App Store 3.1.x).

### 5.10 🔴 CLAUDE: ACTION REQUIRED — apply mint / coupons / provenance migration
> **CLAUDE / AGENT TODO (owner will do this later — do not assume it is done):**
> Paste `docs/migrations/2026_v2_mint_coupons_provenance.sql` into the Supabase SQL Editor and Run.
> Until then: coupon apply fails in prod (`code` ambiguous on the old function), `attach_mint_order` is missing, and free mint with `LOCOLO100` cannot be QA'd against live.
> After applying: check off the verify steps below and remove this CLAUDE marker from the status header + the SQL file header.

Canonical SQL is `docs/migrations/2026_v2_mint_coupons_provenance.sql` (idempotent; fixes the broken prod `preview_mint_fee` and adds `attach_mint_order`).

1. Supabase → SQL Editor → paste the file → Run.
2. Verify:
   ```sql
   select * from public.preview_mint_fee(NULL);         -- fee 2.99
   select * from public.preview_mint_fee('LOCOLO100');  -- total 0, valid true
   select * from public.preview_mint_fee('NOPE');       -- valid false
   select code, discount_type, discount_value, used_count from public.coupons;
   ```
3. From a shell (anon key is enough for preview):
   ```bash
   curl -s -X POST "$URL/rest/v1/rpc/preview_mint_fee" \
     -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
     -H "Content-Type: application/json" \
     -d '{"p_coupon":"LOCOLO100"}'
   # expect total 0 — NOT 42702 ambiguous code
   ```
4. In the app: Create → apply `LOCOLO100` → "Mint for free" → asset appears; Activity/Marketplace provenance shows a `mint` row.

### 5.11 🔴 CLAUDE: ACTION REQUIRED — apply stories migration (Phase D)
> **CLAUDE / AGENT TODO (owner will do this later — do not assume it is done):**
> Paste `docs/migrations/2026_v2_stories.sql` into the Supabase SQL Editor and Run.
> Until then: `StoryStore` sets `available = false` and Explore hides the story rail. Immersive feed still works (no new tables).
> After applying: verify the rail loads for a signed-in user who follows someone with an active story (or posts one), then remove this CLAUDE marker from the status header + the SQL file header.

Canonical SQL is `docs/migrations/2026_v2_stories.sql` (idempotent; `stories`, `story_views`, `get_story_rail`, `mark_story_viewed`, `prune_expired_stories`).

1. Supabase → SQL Editor → paste the file → Run.
2. Verify:
   ```sql
   select proname from pg_proc where proname in ('get_story_rail','mark_story_viewed');
   select tablename from pg_tables where schemaname='public' and tablename in ('stories','story_views');
   ```
3. In the app: Explore → "Your story" → share a photo → ring appears; open viewer advances + marks viewed.

### 5.12 🔴 CLAUDE: ACTION REQUIRED — apply boards migration (Phase D)
> **CLAUDE / AGENT TODO (owner will do this later — do not assume it is done):**
> Paste `docs/migrations/2026_v2_boards.sql` into the Supabase SQL Editor and Run.
> Until then: `BoardsStore` sets `available = false`; Creator Studio → Boards and "Save to board" show a coming-soon empty state.
> After applying: create a board, save an asset from a detail sheet, open the board grid — then remove this CLAUDE marker from the status header + the SQL file header.

Canonical SQL is `docs/migrations/2026_v2_boards.sql` (idempotent; `boards`, `board_items`, `get_user_boards`, `get_board_item_ids`). Spec name "collections" maps to table `boards` (avoids clash with owned-asset "My Collection").

1. Supabase → SQL Editor → paste the file → Run.
2. Verify:
   ```sql
   select proname from pg_proc where proname in ('get_user_boards','get_board_item_ids');
   select tablename from pg_tables where schemaname='public' and tablename in ('boards','board_items');
   ```
3. In the app: Profile → Boards → New board → from any asset "…" → Save to board.

### 5.13 🔴 CLAUDE: ACTION REQUIRED — apply hashtags migration (Phase D)
> **CLAUDE / AGENT TODO (owner will do this later — do not assume it is done):**
> Paste `docs/migrations/2026_v2_hashtags.sql` into the Supabase SQL Editor and Run.
> Until then: `TagStore` hides trending tags; Create → Tags field is a no-op against live.
> After applying: mint with tags → Search shows "Trending tags" → tap `#slug` filters by tag — then remove this CLAUDE marker.

Canonical SQL is `docs/migrations/2026_v2_hashtags.sql` (`tags`, `asset_tags`, `set_asset_tags`, `get_trending_tags`, `get_asset_tags`, `get_assets_by_tag`).

1. Supabase → SQL Editor → paste → Run.
2. Verify: `select * from public.get_trending_tags(10);`
3. Create → add tags → Search → Trending tags chip.

### 5.14 🔴 CLAUDE: ACTION REQUIRED — apply passport / leaderboard migration (Phase D)
> **CLAUDE / AGENT TODO (owner will do this later — do not assume it is done):**
> Paste `docs/migrations/2026_v2_passport.sql` into the Supabase SQL Editor and Run.
> Until then: `ProgressStore` stays unavailable; Explorer Passport keeps using local-only XP; Leaderboard shows coming-soon.
> After applying: open the app (daily_open XP), find an asset in AR, open Profile → XP Leaderboard — then remove this CLAUDE marker.

Canonical SQL is `docs/migrations/2026_v2_passport.sql` (`user_progress`, `award_progress`, `get_my_progress`, `get_xp_leaderboard`).

1. Supabase → SQL Editor → paste → Run.
2. Verify: `select * from public.award_progress('daily_open'); select * from public.get_xp_leaderboard(10);`
3. Profile → XP Leaderboard shows your row.

### 5.15 🔴 CLAUDE: ACTION REQUIRED — apply reposts migration
Paste `docs/migrations/2026_v2_reposts.sql` → Run. Until then Re-drop control hides. Verify: `select public.toggle_repost('<asset uuid>');`

### 5.16 🔴 CLAUDE: ACTION REQUIRED — apply comment threads migration
Paste `docs/migrations/2026_v2_comment_threads.sql` → Run (after social). Adds `parent_id` + `comment_likes`. Until then replies stay flat @mentions and likes hide.

### 5.17 🔴 CLAUDE: ACTION REQUIRED — apply weekly quests migration
Paste `docs/migrations/2026_v2_quests.sql` → Run **after** §5.14 passport (needs `award_progress`). Until then Passport "This week" is empty.

### 5.18 🔴 CLAUDE: ACTION REQUIRED — apply Phase B fiat migration
Paste `docs/migrations/2026_v2_marketplace_phase_b.sql` → Run. `payment_intents` / `payouts` / `create_payment_intent`. Partner `onramp-session` edge fn still required for Apple Pay / card. Until then paid mint creates no intent.

### 5.19 🔴 CLAUDE: ACTION REQUIRED — apply Phase C on-chain foundation
Paste `docs/migrations/2026_v2_marketplace_phase_c.sql` → Run (after Phase A wallets). `nft_tokens`, `link_wallet`, `seaport_order` column. No mainnet contracts until Security audit. Settings → Wallet link works after this.

### 5.20 🔴 CLAUDE: ACTION REQUIRED — apply Phase D social Tier 2–3
Paste `docs/migrations/2026_v2_social_tier23.sql` → Run **after** §5.11–§5.17. Adds `asset_remixes`, `asset_collabs`, `asset_reactions` (+ toggle/summary RPCs), `asset_polls` / votes, `explorer_presence` (+ upsert/nearby RPCs), `ar_events` / RSVPs, `close_friends`, `user_mutes`, comment `pinned` / `hidden_by_creator`. Client stores degrade until applied (`ReactionStore`, `RemixStore`, `PollStore`, `PresenceStore`, `EventsStore`, `SafetyExtrasStore`, `CollabStore`).

### 5.21 🔴 CLAUDE: ACTION REQUIRED — apply auction place_bid / settle RPCs
Paste `docs/migrations/2026_v2_marketplace_auctions.sql` → Run after Phase A. `place_bid` + `settle_auction`. Marketplace sheet falls back to direct bid insert if missing (no outbid cascade).

### 5.22 🔴 CLAUDE: ACTION REQUIRED — apply V2 notification type extras
Paste `docs/migrations/2026_v2_notifications_extra.sql` → Run after `2026_ar_notifications.sql` and §5.20. Extends `notifications.type` check + prefs columns (`reposts`, `reactions`, `quests`, `sales`, `events`) and triggers for repost/reaction/remix/collect. Wire `ActivityStore` kinds + Settings toggles already coded.

### 5.23 🟡 Client-complete — group chat scaffold (E2E later)
No SQL. 1:1 E2E chat remains. Group sender-keys / multi-device is a later crypto pass — do not store plaintext. Track under Security + chat identity (§5.8).

### 5.24 🟡 Client-complete — Gen-Z UX polish (no SQL)
Celebrations (`CelebrationBurst` / `.celebration`), Explore rails (trending near you / drops today / events / presence), onboarding interests seed (`ar.onboarding.interests`), share-to-story from find banner + AR snapshot, immersive reactions + board save, Studio events link + animated XP. Device QA still required.

### 5.25 🟡 Edge stubs — deploy when partners ready
`supabase/functions/onramp-session` (Phase B — iOS already calls it), `chain-webhook` (Phase C), `snapshot-portfolio`, `firebase-custom-token`, and `purge-storage` are stubbed in-repo. Deploy + partner keys + legal/audit still required before live money/chain. `send-push` maps V2 types.

### 5.26 🔴 CLAUDE: ACTION REQUIRED — extend get_* RPCs with `owner_id`
Paste `docs/migrations/2026_v2_rpc_owner_id.sql` → Run after Phase A. Appends `owner_id` to `get_nearby_assets_full` / `get_asset_full` / `get_recommended_assets` (SECURITY INVOKER). Swift already optional-decodes `owner_id`. Until applied, Collection/Marketplace fall back to `userId` via `DigitalAsset.effectiveOwnerId`.

### 5.27 🔴 CLAUDE: ACTION REQUIRED — storage cleanup for deleted accounts
Paste `docs/migrations/2026_v2_storage_cleanup.sql` → Run. Creates `pending_storage_deletes` + `enqueue_storage_cleanup`, and redefines `delete_my_account` to enqueue Storage paths **before** row deletes. Deploy `supabase/functions/purge-storage` (cron, `--no-verify-jwt`, optional `PURGE_CRON_SECRET`). Until applied, account delete still leaves orphaned files.

### 5.28 🔴 CLAUDE: ACTION REQUIRED — extend trigger_type CHECK
Paste `docs/migrations/2026_v2_trigger_types.sql` → Run. Prod CHECK still allows only `tap|proximity|speech|shake`. Client also writes `gaze`, `time_of_day`, `long_press`, `multi_tap`, `walk_around` — mint fails for those until applied.

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
12. **Notifications are written by the database, never the client.** Add a new event as a trigger calling `_notify()` (which applies self, block and dedupe rules), add its copy in `send-push` and `ActivityStore.localCopy`, map it in `NotificationPrefs.allows(type:)`, and render it in `ARActivityView`. Push payloads never carry chat text. Keep `NotificationManager` as the only `UNUserNotificationCenter` delegate, and register categories there in one `setNotificationCategories` call (it replaces the set).

## 6b. 🟢 V2 migration batch — APPLIED 2026-09-28 (all §5.10–§5.28 SQL)

All sixteen pending V2 migrations were applied to prod via Supabase MCP and verified
(28/28 tables, 29/29 RPCs, 7/7 new triggers, 65 RLS-enabled tables, 5 quests seeded,
2 active coupons, security advisor shows **no ERROR-level findings**).

**Deviations from the .sql files — the files as written will FAIL if re-run verbatim.
Fix the files before reusing them:**

1. **`2026_v2_rpc_owner_id.sql` — `SET search_path = public` is wrong.** PostGIS
   `geometry`/`geography` live in the `extensions` schema, so the function bodies fail
   with `42704: type "geometry" does not exist`. Applied with
   `SET search_path = public, extensions`. Also `CREATE OR REPLACE` cannot change a
   function's return type — the RPCs had to be `DROP`ped first (41 → **42 columns**,
   `owner_id` appended; `DigitalAsset.ownerId` is optional so decoding is unaffected).
2. **`2026_v2_stories.sql` — partial index predicate used `now()`**, which isn't
   IMMUTABLE; Postgres rejects it. Applied `stories_active_idx` without the
   `WHERE expires_at > now()` clause (RLS/RPCs still filter on expiry).
3. **`2026_v2_mint_coupons_provenance.sql` required reconciliation.** An earlier draft
   of this layer was already live with an incompatible shape (`provenance_records` with
   NOT NULL `seq`/`canonical` and a 2-value `event_type` CHECK; `mint_orders` status CHECK
   without `'consumed'`). Both tables had 0 rows, so they were dropped and recreated from
   the canonical file; the draft `on_asset_mint` trigger + `get_provenance` RPC were
   dropped, and `buy_listing` was reverted to pure settlement (the canonical
   `trades_provenance_sale` trigger now writes sale provenance).
4. **plpgsql identifier clashes** renamed while applying: `row` (reserved) →
   `cur`/`created` in `award_progress` / `create_payment_intent`; `bid_id` → `new_bid`
   and `trade_id` → `new_trade` in `place_bid` / `settle_auction` (they shadowed the
   `RETURNING ... INTO` target columns).

**Still true after this batch:** `TESTAPRAM6800621` *and* `LOCOLO100` both preview at
total $0. `preview_mint_fee` ambiguity is fixed (no more 42702). `app_config.push_enabled`
remains `false` (local notification fallbacks stay on until `send-push` is deployed).
The only RLS-enabled table without a policy is `pending_storage_deletes` — intentional
(service-role only).

## 7. Remaining work & known gaps

| Priority | Item | Runbook |
|---|---|---|
| ✅ | ~~apply `2026_v2_mint_coupons_provenance.sql`~~ **APPLIED 2026-09-28** | §5.10 |
| ✅ | ~~apply `2026_v2_stories.sql`~~ **APPLIED** | §5.11 |
| ✅ | ~~apply `2026_v2_boards.sql`~~ **APPLIED** | §5.12 |
| ✅ | ~~apply `2026_v2_hashtags.sql`~~ **APPLIED** | §5.13 |
| ✅ | ~~apply `2026_v2_passport.sql`~~ **APPLIED** | §5.14 |
| ✅ | ~~apply `2026_v2_reposts.sql`~~ **APPLIED** | §5.15 |
| ✅ | ~~apply `2026_v2_comment_threads.sql`~~ **APPLIED** | §5.16 |
| ✅ | ~~apply `2026_v2_quests.sql`~~ **APPLIED** | §5.17 |
| ✅ | ~~apply `2026_v2_marketplace_phase_b.sql`~~ **APPLIED** | §5.18 |
| ✅ | ~~apply `2026_v2_marketplace_phase_c.sql`~~ **APPLIED** | §5.19 |
| ✅ | ~~apply `2026_v2_social_tier23.sql`~~ **APPLIED** | §5.20 |
| ✅ | ~~apply `2026_v2_marketplace_auctions.sql`~~ **APPLIED** | §5.21 |
| ✅ | ~~apply `2026_v2_notifications_extra.sql`~~ **APPLIED** | §5.22 |
| 🟡 | Group chat E2E (scaffold only) | §5.23 |
| 🟡 | Device QA UX polish pass | §5.24 |
| 🟠 | Deploy `onramp-session` + `chain-webhook` + `snapshot-portfolio` + updated `send-push` | §5.25 |
| ✅ | ~~apply `2026_v2_rpc_owner_id.sql`~~ **APPLIED** (RPCs now 42 cols) | §5.26 |
| ✅ | ~~apply `2026_v2_storage_cleanup.sql`~~ **APPLIED**; still deploy `purge-storage` | §5.27 |
| ✅ | ~~apply `2026_v2_trigger_types.sql`~~ **APPLIED** | §5.28 |
| 🟠 | Commit + push all V2 Swift + migrations | §5.2 |
| 🟠 | Contract audit + partner onramp keys | `LOCOLO_V2_MARKETPLACE.md` / Security |
| ✅ | Minting Swift + Phase A list/buy/provenance/portfolio UI (code, uncommitted) | §4.10 |
| 🟠 | APNs key + Push capability + `send-push` + webhook + `push_enabled` | §5.3c steps 2–6 |
| 🟡 | Chat identity binding — client + edge stub ready; need Firebase SA + Admin mint | §5.8 |
| 🟠 | Deploy edge functions + backfill embeddings | §5.4 / §5.25 |
| 🟠 | On-device field testing (AR polish + minting + social) | §5.7 |
| 🟠 | Moderation process owner | §5.6 |
| 🟡 | Extend `DigitalAsset` + read RPCs with optional `owner_id` / authenticity fields | §6.1 / §4.10 |
| 🟡 | Push `fresh-start` → then fast-forward GitHub `main` | §5.2 |
| 🟡 | Widget Extension target in Xcode (`LocoloWidgets/` sources ready) | polish |
| ✅ | V1 migrations (safety / social / notifications / flat-view) | §5.3–5.3c |
| ✅ | V2 Phase A trading DB foundation | `2026_v2_marketplace_phase_a.sql` |
| ✅ | Prod RPC dump | `2026_prod_rpcs_dump.sql` |

**Engineering-health (audited 2026-09-28, stage 19):**
- ✅ **Unit tests** — `LocoloTests` target in pbxproj + `MarketplaceMathTests`.
- ✅ **Crashlytics + Analytics** — SPM products + `LocoloAnalytics` (dSYM upload still owner/CI).
- ✅ **Logging hygiene (hot AR/mint)** — create/placement/viewer media paths use `LocoloLog`; no precise coords in those logs. Legacy `Views/` `print`s can wait.
- 🟡 **Legacy non-AR code still in the build** — park closer to release (owner).
- 🟡 **No localization** — String Catalog when targeting non-English markets.
- Good signals: 0 `try!` force-unwraps; dead `AssetDetailViewModel` removed.
- ✅ **Location usage copy** — AR-framed `NSLocation*` strings in pbxproj.

Smaller gaps: push delivery needs §5.3c + deploy updated `send-push`. Until then alerts are local. Full-text search is client-side (`search_tsv` unused); 40-entity cap is per placement pass; Collection ownership improves after §5.26; key rotation / multi-device chat crypto still limited.

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

- **2026-09-28 (stage 19, uncommitted) — Client ship-ready pass:**
  - Marketplace: post-trade `get_asset_full` refresh on detail sheet; Phase B `PaymentService.startCheckout` → `onramp-session` from mint paywall.
  - SQL: `2026_v2_trigger_types.sql` (§5.28) for new trigger CHECK values.
  - UX: Activity filter chips Social/Sales; AR location usage strings; hot AR/mint `print` → `LocoloLog`.
  - **Verdict:** no further in-repo client work for ship — owner SQL/deploy/partners/QA only.
- **2026-09-28 (stage 18, uncommitted) — Docs leftovers complete (client):**
  - AR: clip→Story (`ARClipRecorder`); triggers gaze / time-of-day / long-press / multi-tap / walk-around; create Preview trigger; draw brushes tube/ribbon/neon; placement contact shadow + true-size; `ExploringLiveActivity` + widget UI source.
  - Eng: Crashlytics + Analytics SPM in pbxproj; `LocoloAnalytics`; `LocoloTests` XCTest target; `NSSupportsLiveActivities`.
  - Edge/SQL: `firebase-custom-token` stub; `purge-storage` + `2026_v2_storage_cleanup.sql` (§5.27, wires `delete_my_account`).
  - Docs: completion plan / polish / status synced — remaining work is owner SQL/deploy/partners/QA.
- **2026-09-28 (stage 17, uncommitted) — Docs leftovers pass:**
  - Create: collab picker + poll fields; `HoloCard` on Featured; rare-find haptic/copy; trigger particle burst; payouts read UI; group-chat scaffold sheet.
  - Edge: `send-push` V2 type map; `snapshot-portfolio` stub; SQL `2026_v2_rpc_owner_id.sql` (§5.26).
  - Eng: `LocoloLog`, `MarketplaceMath` + `LocoloTests/` sources; deleted dead `AssetDetailViewModel`.
- **2026-09-28 (stage 16, uncommitted) — V2 remainder: reposts, threads, quests, Phase B/C foundations:**
  - **SQL (CLAUDE apply §5.15–§5.19):** `2026_v2_reposts.sql`, `2026_v2_comment_threads.sql`, `2026_v2_quests.sql`, `2026_v2_marketplace_phase_b.sql`, `2026_v2_marketplace_phase_c.sql`.
  - **Social:** `RepostStore` + Re-drop on feed cards; threaded replies + comment likes; weekly quests on Passport card.
  - **Marketplace:** `PaymentService` + paid-mint intent; `WalletService` + Settings wallet link; nft_tokens / Seaport column schema.
- **2026-09-28 (stage 15, uncommitted) — Phase D Passport sync + leaderboard:**
  - **SQL in repo:** `2026_v2_passport.sql` — `user_progress`, `award_progress`, `get_xp_leaderboard`. **Apply (§5.14).**
  - **Client:** `ProgressStore` (discover/create/daily_open); Profile → XP Leaderboard; local Passport card unchanged as fallback.
- **2026-09-28 (stage 14, uncommitted) — Phase D hashtags:**
  - **SQL in repo:** `2026_v2_hashtags.sql`. **Apply to prod (§5.13).**
  - **Client:** `TagStore`; Create tags field; Search trending tags + `#slug` results; detail sheet tag chips.
- **2026-09-28 (stage 13, uncommitted) — Phase D boards:**
  - **SQL in repo:** `2026_v2_boards.sql` — `boards` / `board_items`, `get_user_boards`, `get_board_item_ids`. **Apply to prod (§5.12).**
  - **Client:** `BoardsStore` in `SocialSession`; `BoardsListView` / `BoardDetailView` / `SaveToBoardSheet`; Creator Studio → Boards; asset "…" → Save to board.
- **2026-09-28 (stage 12, uncommitted) — Phase D Tier 1: stories + immersive For You feed:**
  - **SQL in repo:** `2026_v2_stories.sql` — `stories` / `story_views`, `get_story_rail`, `mark_story_viewed`. **Apply to prod (§5.11).** Client hides the rail until applied.
  - **Client:** `StoryStore` in `SocialSession`; `StoryRailView` + `StoryViewer` on Explore; `ImmersiveFeedView` full-screen vertical pager (Swipe toggle on Shared Space). Hype/comments/wishlist via shared stores.
- **2026-09-28 (stage 11, uncommitted, build green) — minting + Phase A marketplace client:**
  - **SQL in repo:** `2026_v2_mint_coupons_provenance.sql` — coupons (`discount_type`/`discount_value`), mint_orders, provenance_records, fixed `preview_mint_fee`, `create_mint_order`, `attach_mint_order`, mint+sale provenance triggers, seeds `LOCOLO100`. Locally tested. **Apply to prod (§5.10).**
  - **Mint client:** Ed25519 signing, content hash, mint paywall + coupon, attach order after insert.
  - **Marketplace client:** `MarketplaceRepository` / `MarketplaceSheet` (list, cancel, buy via `buy_listing`), provenance timeline, portfolio snapshots chart on Creator Studio, optional `DigitalAsset.ownerId`.
- **2026-09-28 — V2 Phase A trading DB** committed as `626b940`.
- **2026-09-28 (stage 10) — share AR asset in chat (Instagram-style) + AR polish backlog:** new `AssetShareService` (find-or-create conversation → send `locolo://asset/<id>` through the normal E2E send path — no new crypto/schema). `ChatView` detects an asset-link message and renders a tappable rich `AssetShareBubble` (async-loads via `get_asset_full`, opens the detail sheet); `AssetDetailSheet` "…" menu gains **Send in a message** → reuses `ARNewMessageSheet` people-picker → toast on send. Build green. Also added `docs/LOCOLO_AR_POLISH.md` (prioritized AR enhancement backlog).
- **2026-09-28 (stage 9) — DB migrations applied to prod:** ran `2026_ar_safety_and_hardening.sql`, `2026_ar_social.sql`, `2026_ar_notifications.sql` via MCP, plus `2026_ar_flat_view_rls.sql` (new). RLS now on for all 26 public tables (86 policies); the critical anon email/hype exposure is closed; read RPCs are SECURITY INVOKER; comments + the notifications backend (triggers, prefs, device tokens, cross-device read state) are live with `push_enabled=false`. Verified via security advisor: the RLS-disabled critical is gone and the SECURITY DEFINER view ERROR is fixed.
  - **Residual advisor findings (reviewed, non-blocking):** (a) 34 legacy functions have a mutable `search_path` (WARN — the AR functions added here all pin `search_path=public`; the rest are pre-existing loop/place helpers); (b) `pg_trgm`/`vector` live in the `public` schema (WARN, cosmetic); (c) GraphQL "table visible to anon/authenticated" lints — informational, RLS still gates every row; (d) a few SECURITY DEFINER RPCs are callable by anon/authenticated by design (`email_registered` needs anon for the forgot-password check; `toggle_asset_hype`/`notify_message`/`register_device_token` self-authorize via `auth.uid()`); (e) leaked-password protection is a dashboard Auth toggle (enable in Supabase → Auth → Passwords). None block launch.
- **2026-09-27 (stage 8) — committed:** committed stage 7 (notifications) so it isn't lost; captured the 5 prod-live RPCs (`get_nearby_assets_full`, `get_asset_full`, `get_recommended_assets`, `get_follow_counts`, `toggle_asset_hype`) into `docs/migrations/2026_prod_rpcs_dump.sql` (they existed only in prod). Full build green. `get_comment_counts` intentionally excluded (ships with the unapplied social migration).
- **2026-09-27 (stage 7) — committed:** notifications (§4.9).
  - Server: `notifications` table fed by triggers for follows, hypes, comments, @mentions, offers and offer answers, new drops to followers, discoveries, hype/explorer milestones, and messages (`notify_message`). Plus notification preferences, APNs device tokens, cross-device chat read state (`conversation_reads`), and the `app_config.push_enabled` flag (`2026_ar_notifications.sql`). New `send-push` edge function (direct APNs with an ES256 JWT, prefs, badge, thread and collapse ids, stale-token cleanup).
  - Client: the Activity screen reads the server feed with cross-device read state and swipe to clear, and shows the new kinds. Local-notification fallbacks run until push is live. Notification taps route through `DeepLinkRouter` (new chat, activity, messages and viewer links). The chat you're reading shows no banner. App badge sync.
  - Nearby AR art alert within 100 m: exact distance, direction, name, creator, place, thumbnail, View in AR action, hysteresis, cooldowns, and geofences for a killed app.
  - Settings: notification toggles and a permission prompt. The token is unregistered on sign-out.
- **2026-09-27 (stage 6) — `9f73f48`, AR module only:** social network layer (§4.8). Shared engagement/follow/inbox/activity stores; comments (UI + `2026_ar_social.sql`); redesigned feed card with double-tap hype; creator row + follow on the detail sheet; Explore Following filter, creator suggestions, skeletons and badged Activity/Messages; Activity screen; rebuilt Messages inbox with unread state; centre Create tab; profile cover/share/edit; AR Edit Profile; Search Creators rail; `locolo://user/<id>` deep links.

- **2026-09-27 (stage 5b) — `0393ca9`, pushed to `github/fresh-start`:** audit follow-ups. Chat via `ARChatScreen` on the dashboard stack; visibility filters + server-side visibility RLS; Keychain-safe identity key; notification-extension ciphertext guard; Firebase session follows Supabase login; robust logout; `view_count` trigger; profile placement map; Geo ⇄ GPS toggle; GPS-mode re-anchoring; hype in-flight guard; follow-list error + Retry; removed no-op post toggle; removed `AppDelegate` plaintext reply path.
- **2026-09-27 (stage 5) — in `0393ca9`:** verification pass against code + prod. Fixed viewer lifecycle, radians/degrees, media cache, hand-draw export pipeline, feed refresh, chat plaintext fallback/quick-reply/listener leak, offers, wishlist, deep-link cold launch, `.create` owner fallback, Info.plist. Added report/block/settings/delete account, snapshots, hot/cold finder, Explorer Passport, email-private data layer, hardened edge functions, safety & hardening migration.
- **2026-09-27 (stage 4) — in `0393ca9`:** ciphertext-notification fix, `locolo://asset/<id>` deep links + `get_asset_full`, post-save share, taste-vector wiring, first-launch onboarding.
- **2026-09-27 (stage 3) — `9938d2f`:** de-stubbed AssetDetailSheet, profile messaging, key-change banner, chat restyle + search, semantic search rail, AR radar, category fix, `toggle_asset_hype`.
- **2026-09-27 (stage 2) — `329cf3c`:** WS0/2/3/4/8, WS5 code, WS6 core, WS7, UI polish, Mapbox removal.
- **2026-09-27 (stage 1):** WS1 DB migration applied to prod; `get_recommended_assets` added.
