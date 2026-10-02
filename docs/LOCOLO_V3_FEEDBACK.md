# LOCOLO V3 — Owner feedback batch (2026-10-02)

Status of every item from the owner's "things that need to be done" list. Build green
(`xcodebuild … iPhone 17 Pro` sim). All new code is uncommitted in the working tree.

## Owner actions (code is done; these unlock it)

> Superseded for release by `docs/LOCOLO_RELEASE_CHECKLIST.md`.

| # | Action | Unlocks |
|---|---|---|
| 1 | ~~Run `docs/migrations/2026_v3_offers_fix.sql`~~ ✅ applied 2026-10-03 via MCP (`v3_offers_fix`) | Accept / reject offers (fixes `offers_status_check`) |
| 2 | ~~Run `docs/migrations/2026_v3_memories_posts_growth.sql`~~ ✅ applied 2026-10-03 (`v3_memories_posts_growth`, + `v3_storage_paths`, `v3_advisor_fixes`) | Memories, Reels, posts, growth charts, asset settings RPC, background alert sounds |
| 3 | Supabase → Auth → **Email templates → "Confirm signup"**: body must contain `{{ .Token }}` (6-digit code), not only `{{ .ConfirmationURL }}`. Same for **Magic Link** (used by Forgot password). | Email verification codes |
| 4 | Supabase → Auth → **SMTP**: configure a custom SMTP sender (Resend / Postmark / SES). The built-in sender only delivers to project team addresses and is rate-limited to a few emails/hour — the most likely reason codes "aren't sent". | Email delivery |
| 5 | Supabase → Auth → Providers: enable **Apple** (Services ID + key) and **Google** (OAuth client). Add `locolo://login-callback` under URL Configuration → Redirect URLs. | Sign in with Apple / Google |
| 6 | Apple Developer → App ID `com.apram.locolo` → enable **Sign in with Apple** (entitlement file `Locolo/Locolo.entitlements` is already wired). | Apple sign-in on device |
| 7 | Google Cloud → project of the Maps key → **enable billing** + Street View Static API. Probe today returns `REQUEST_DENIED: You must enable Billing`. | Google Street View (Apple Look Around is used meanwhile) |
| 8 | Deploy `firestore.rules` once chat identity binding (§5.8) is live — groups reuse the `participants` rules unchanged. | Chat access control |

## Item-by-item

| Feedback item | Done | Where |
|---|---|---|
| AR world title → **Loco AR** | ✅ | `ARExploreView`, onboarding, tab-bar a11y |
| Asset preview: less zoomed, no black background | ✅ camera fitted to bounding sphere with padding, transparent SceneKit over thumbnail-tinted aurora stage, orbit/pinch/double-tap reset, IBL lighting, MediaCache | `AssetSceneView.swift` |
| Thumbnail / memory on an asset | ✅ owners upload a custom thumbnail; anyone captures memories | `AssetManageSheet`, `MemoryComposerView` |
| Memories (memos) per asset, shareable to feed, snap-style | ✅ AR shutter (tap = photo, long-press = clip) → composer (caption w/ on-device suggestions, pick asset, Reels toggle, visibility, Story, Photos, send to friends); snap viewer (progress bars, tap/hold/swipe-down, double-tap like) | `MemoryStore`, `MemoryViews.swift`, `ARDisplayView` |
| Swipe mode → Reels of memories + "Inspect asset" button | ✅ vertical paging Reels over shared memories; Explore "Reels" button + memories rail | `MemoryReelsView` |
| Posts: full-width media, cooler background | ✅ edge-to-edge 4:5 media, artwork floats on its own colour stage + blurred echo | `ARSocialAssetCard` / `AssetPostMedia` |
| Share like Instagram (recents, search, send) in every share button | ✅ `ARShareSheet`: recent chats + follows grid, multi-select, search, message, copy link, post about it, external | used by detail sheet, feed card, Reels, memories, posts, profiles, immersive feed |
| Detail sheet: Make offer unreachable | ✅ single scroll + **pinned action bar** (View in AR/Directions + Buy/Make offer/View offers + Marketplace) | `AssetDetailSheet` |
| Offers accept/reject check-constraint error | ✅ code + SQL (#1); friendly errors | `OfferRepository`, `OfferViewModel` |
| Other user's profile: 4 sections + share profile | ✅ Passport/stats · Map (placed + owned) · Memories & posts · Reposts; share via share sheet | `ProfileTabs.swift`, `CreatorProfileView` |
| Posts linking other posts + own images/memories | ✅ composer (text, ≤4 photos, link to post/asset/memory, visibility, on-device hashtag ideas); quote posts; posts interleaved in Explore | `PostStore`, `PostViews.swift` |
| Map: start zoomed to 5 km around user; navigate to asset | ✅ 5 km square on first fix + "center on me"; in-app MapKit route (walk/drive/transit, ETA, steps, re-route) + Apple Maps hand-off; Directions on cards & sheet | `ARNearbyView`, `AssetNavigationView` |
| Search assets on the map | ✅ live filter + server name/description search | `ARNearbyView`, `AssetSearch` |
| AR background mode with audio alerts | ✅ "BG" toggle in AR viewer; keeps location + audio sessions alive, plays creator alert sound (or the asset's audio) on approach, notification to reopen. ARKit itself can't render in background (iOS limit). `audio` background mode added. | `BackgroundExploreService` |
| Google Street View | ✅ code: metadata probe + clear reasons + Apple Look Around fallback. ⚠️ Google needs billing (#7) | `ARNearbyView` |
| Asset settings sheet with growth graphs | ✅ trading-style line chart (range 1W–ALL, metrics, scrubbing, green/red delta), accept offers, visibility, name/description/thumbnail, alert sound + radius, delete | `AssetManageSheet` |
| Core ML / Apple AI | ✅ free on-device: Vision scene labels → caption & hashtag ideas; Foundation Models (iOS 26 Apple Intelligence) captions; NaturalLanguage harsh-comment nudge | `SmartSuggestions` |
| Chats "just like …" | 🟡 sentence was cut off — assumed Instagram DMs: date separators, grouped bubbles, rich cards for assets/memories/posts/profiles, copy. **Confirm intent.** | `ChatView` |
| Login error shown on sign-up screen | ✅ every auth screen owns its error state and clears shared banners on appear | `AuthStartView` |
| Verification code not sent | ✅ resend button + 60 s cooldown, unverified sign-in jumps to code screen. Delivery itself = owner #3/#4 | `UserViewModel.resendSignupCode` |
| Wrong code says "expired" | ✅ Supabase returns one error for both; we use code age (< 1 h ⇒ "isn't right") | `AuthErrorMapper` |
| Sign in with Apple / Google / email | ✅ | `AuthStartView`, `UserViewModel` (owner #5/#6) |
| "Profile is still being set up" | ✅ missing profile row is created on the spot (login, restore, OTP, OAuth) | `UserViewModel.completeSignIn` |
| Creation of groups | ✅ E2E group chats via per-member fan-out (no plaintext, no group key); create, info, add, rename, leave | `GroupChatViews`, `ChatViewModel`, `ChatRepository` |

## Also fixed along the way
- Forgot password used `signInWithOTP` with default `shouldCreateUser: true` → typing any email created an account. Now `shouldCreateUser: false`, no account enumeration.
- `findExistingConversation` would have matched group threads as 1:1 DMs.
- Nearby map never moved to the user (camera stayed `.automatic`).

## Not verified
- Everything AR/camera/background-audio is device-only — untested on hardware.
- ~~New SQL not applied~~ Applied 2026-10-03 — see "Schema fixes at apply time" below.

## Schema fixes at apply time (2026-10-03)
Checked against the live DB before applying:
- **`posts` already existed** as the legacy main-app table (`author_id`, `description`, `loop_id NOT NULL`, 27 rows,
  FKs from `echoes` / `hypes` / `real_memories`, used by `PostsRepository` / `ProfileViewModel`). V3 posts now live in
  **`user_posts`** / **`user_post_likes`** (policies `up_*` / `upl_*`); `PostStore` updated to match. Legacy `posts` untouched.
- Legacy `offers_status_check` was `(pending, accepted, declined, cancelled)`; app, `notify_on_offer` and the
  `offers_update_*` policies already used `rejected` / `withdrawn`. All 14 live offers were `pending`, so no rows rewritten.
  Also `offers.status SET NOT NULL` and a new `offers_asset_status_idx`.
- `update_asset_settings`: `greatest(NULL, 10)` is 10 in Postgres, so every save without a radius reset
  `alert_radius_m` to 10 m — now only changed when passed. Ownership checks use `IS DISTINCT FROM` (NULL owner no longer passes);
  same in `get_asset_growth`.
- RLS uses `(select auth.uid())` (advisor `auth_rls_initplan`); covering indexes for the new FKs; anon `REVOKE`d on the 5 new tables.
- Storage: `media` already allowed any authenticated INSERT anywhere; added RESTRICTIVE own-folder policies for
  `memories/` and `posts/` only (`2026_v3_storage_paths.sql`). `media` has a **3 MB** file limit — memory videos above that fail.
- Verified: `respond_to_offer` smoke-tested in a rolled-back txn (owner accept → winner `accepted`, 2 competitors `rejected`,
  `active_offers` 0; non-owner 42501; re-respond refused; anon denied). RPC rows match `AssetMemory`, `UserPost`,
  `AssetGrowthPoint`, `AlertRow`. Build green.
