# Locolo AR — Standalone App Release Specification

**Status:** Implementation-ready specification
**Audience:** An AI coding agent (or engineer) executing the build. Written to be self-contained.
**Repo root for all paths below:** `/Users/apps/Desktop/LOCOLO/locolo/`
**App target:** `Locolo` (Xcode project `Locolo.xcodeproj`, filesystem-synced groups — moving/adding files needs **no** manual `project.pbxproj` edits, but **target membership** does matter; see WS0).

---

## 0. How to use this document

This spec turns the existing Locolo app into a **standalone AR-only social app** ("Instagram for real life") and hardens it for release. It is organized into **workstreams (WS0–WS9)**. Each workstream has:

- **Goal** — what done looks like.
- **Why / current state** — the real code today (with file paths) so you have context.
- **Changes** — concrete files to create/edit with signatures.
- **Data model / SQL** — exact DDL where relevant.
- **Algorithms** — pseudocode for anything non-obvious.
- **Acceptance criteria** — testable checklist.

**Execution order (dependencies):** WS1 (DB) → WS0 (extraction) → WS2 (rotation) → WS3 (localization) → WS8 (caching) → WS4 (social) → WS5 (explore) → WS6 (chat E2E) → WS7 (hand-draw) → WS9 (release checklist). WS2/WS3/WS8 are independent of WS4–WS7 and can be parallelized.

**Non-negotiable constraints:**
- `DigitalAsset` (in `Locolo/Models/DigitalAsset.swift`) decodes **directly** from the `get_nearby_assets_full` RPC and other selects. **Swift `CodingKeys` and DB column names must stay in exact lockstep.** Any new column returned by a query that isn't optional in Swift will break decoding for the whole row.
- Permission strings live as `INFOPLIST_KEY_*` **build settings in `project.pbxproj`**, not in `Info.plist`. New permissions (microphone already present for speech triggers; camera present) must be added there.
- The Mac's disk runs near full — purge stale `DerivedData` if builds fail on space.
- iOS target: **iOS 17+**, Swift 5.9+, device-only for AR (simulator is guarded out throughout).

---

## 1. Product vision (target state)

Locolo AR is a location-anchored social network where the "posts" are **3D digital assets placed in the real world**. Users:

1. **Create** assets — upload a USDZ, place it in AR, pick an embedded animation and a trigger (tap/proximity/speech/shake), OR **draw one in the air with hand gestures** (WS7).
2. **Explore** assets — a social feed (For You / Trending / Nearby), a map, and search.
3. **Discover in AR** — walk around and see assets others placed, anchored accurately at their real GPS + orientation.
4. **Follow** other creators, view their **profiles**, and get **personalized recommendations**.
5. **Chat** with **end-to-end encryption**, reachable from inside the AR app.

---

## 2. Current architecture (as-is, verified)

**App entry:** `LocoloApp.swift` (`@main`) injects ~10 `@StateObject` view models as environment objects → `ContentView.swift` → on auth shows `MainView()` (full app), else `AuthStartView()`. Firebase configured in `LocoloApp.init()`; Firebase **anonymous** auth signed in from `ContentView.task`. Supabase session restored via `userVM.restoreSession()`.

**AR module (already isolated):** `Locolo/ARModule/`
- **Shell:** `ARDashboardRootView.swift` — `NavigationStack` + lazy keep-alive `ZStack` of 4 tabs behind a floating glass `ARTabBar`. Tabs: `ARExploreView`, `ARNearbyView`, `ARSearchView`, `ARCreatorDashboardView`. Pushed routes (`ARRoute`): `.viewer` → `ARDisplayView`, `.create` → `ARCreateAssetFlowView`, `.collection`, `.wishlist`. State in `ARDashboardState.swift`.
- **Viewer:** `Viewer/ARDisplayView.swift` (+ `ARViewContainer`, `SharedARViewHolder` singleton) and `Viewer/ARDisplayViewModel.swift` (GeoTracking + GPS/World dual mode, fallback logic). Triggers under `Viewer/Triggers/` (`TriggerEngine`, `ShakeDetector`, `SpeechTriggerService`, `ARMediaPlaybackController`, `TriggerModels`).
- **Creation:** `Creation/ARCreateAssetFlowView.swift` (multi-step), `ARCreateViewModel.swift`, `ARPlacementView.swift` (`UIViewRepresentable` with gesture install + long-press confirm), plus step views (`FileStepView`, `AnimationPickerStepView`, `TriggerConfigView`, `DetailsStepView`, `AddressConfirmationView`).
- **Dashboard/social:** `Dashboard/ARExploreView.swift`, `ARNearbyView.swift`, `ARSearchView.swift`, `ARSocialAssetCard.swift`, `AssetDetailSheet.swift`, `CollectionView.swift`, `WishlistView.swift`, `Offers/`. View models in `ViewModels/` (`ARExploreViewModel`, `ARGalleryViewModel`, `ARProfileViewModel`, `AssetDetailViewModel`, `CollectionViewModel`, `OfferViewModel`).
- **Services:** `Services/AddressService.swift` (CLGeocoder reverse geocode + MKLocalSearch), `Services/SeenAssetsRepository.swift`.
- **Design system:** `ARDesign.swift`.

**Data models:** `Locolo/Models/DigitalAsset.swift` (decodes RPC), `User.swift`, `MessagingModels.swift` (`Message`, `Conversation`), `Offer.swift`, `TriggerModels.swift`.

**Chat (as-is):** Firebase Firestore. `Models/Repositories/ChatRepository.swift` + `ViewModels/ChatViewModel.swift` + `ConversationListViewModel.swift`; UI in `Views/Messages/`. Messages stored **plaintext**; `senderId` = lowercased Supabase UUID written by client; participant filtering **client-side only**; **no security rules**; identity is Firebase **anonymous** (no binding between the anonymous Firebase user and the claimed Supabase `senderId`).

**Backend:** Supabase (Postgres + PostGIS) primary; the RPC `get_nearby_assets_full(p_lat, p_lon, p_radius_meters)` returns rows decoded straight into `DigitalAsset`. Object storage bucket `digital_assets` (paths `DigitalArt/`, `DigitalArtMedia/`). Firebase for chat + anonymous auth + push.

**Known pending migration:** `supabase_ar_dashboard.sql` (repo root) has NOT been applied. It adds `locations.altitude_m`, `locations.altitude_accuracy_m`, `digital_assets.animation_name/animation_index/trigger_type/trigger_config`, the `asset_views` table, and requires re-creating `get_nearby_assets_full` to return the 6 new columns. **Until applied, triggers/animations/address/altitude/Explored do nothing and RPC decode can break.**

---

## WS0 — Standalone AR-only app extraction

**Goal:** App launches straight into the AR experience (after auth), with the non-AR feature set excluded from the build target but preserved in the repo for later versions.

**Why:** The AR module is already isolated behind `ARDashboardRootView`; the rest of the app (Loops, Discover, non-AR posts, events) is dead weight for this release and adds build surface + risk.

### Changes

1. **New root routing.** Edit `ContentView.swift`: replace `MainView()` with a new `ARAppRootView()` for the authenticated branch. Keep `AuthStartView()` for unauthenticated. Keep the `.task` block (session restore, Firebase sign-in, location tracking start) — but see WS6 for replacing anonymous Firebase auth with a bound identity.

2. **Create `Locolo/ARModule/ARAppRootView.swift`:**
   ```swift
   struct ARAppRootView: View {
       @EnvironmentObject var userVM: UserViewModel
       var body: some View { ARDashboardRootView() }   // AR module is the whole app
   }
   ```
   `ARDashboardRootView` already reads `userVM` and `wishlistVM` from the environment and manages its own `NavigationStack`.

3. **Trim environment objects in `LocoloApp.swift`.** The AR module needs: `userVM` (`UserViewModel`), `wishlistVM` (`WishlistViewModel`), `locationManager` (`LocationManager.shared`). It does **not** need `loopVM`, `placeVM`, `postsVM`, `discoverVM`, `createPostVM` (the non-AR post creator), `locationVM` unless the Nearby tab needs it (see step 5). Leave `keyboardObserver` (used widely). Keep injections minimal but do not remove ones that AR sub-views transitively read — verify by compiling.

4. **Target membership (do NOT delete files).** Remove from the `Locolo` target's "Compile Sources" (or move to a `_Parked/` group excluded from the target): `Views/ExploreScreen/`, `Views/Discover Screen/`, `Views/CreateView/` (non-AR post flow), `Views/Posts/`, `Views/ExploreScreen/LoopViews/`, and their VMs/repos (`ExplorePostsViewModel`, `DiscoverViewModel`, `LoopViewModel`, `EventsDiscoverViewModel`, `ActivitiesDiscoverViewModel`, `EventAttendanceViewModel`, `HypeViewModel`, `EchoViewModel`, `PlaceViewModel`, `PlaceDetailViewModel`, `CreatePostViewModel`). **Because groups are filesystem-synced, the cleanest approach is a physical `_Parked/` folder** the target ignores, OR keep them and just don't reference them (they'll still compile — heavier but zero risk). **Recommended: keep-but-don't-reference for the first pass; physically park later** once the app boots AR-only.

5. **⚠️ Nearby tab entanglement.** `ARNearbyView` reuses `MapViewModel` (`ViewModels/MapViewModel.swift`), which likely pulls in Loops/Places. Before parking Loops code, audit `MapViewModel`'s imports. If it depends on Loop clustering (`SupabaseClusterRow`, `ClusterNode`, `LocationsViewModel`), either (a) keep those files in-target, or (b) refactor `ARNearbyView` to a lean AR-only map VM that queries only `digital_assets` near the user. **Recommended for release:** keep `MapViewModel` and its direct deps in-target; defer the refactor.

6. **Auth flow stays.** `AuthStartView`, `SignInView`, `SignUpScreens`, `OTPVerifyView`, `ForgotPasswordEmailView`, `NewPasswordView` remain in-target — the standalone app still needs login.

7. **App identity.** Update display name / bundle id if shipping as a distinct app (`INFOPLIST_KEY_CFBundleDisplayName`, `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj`). Optional for internal release.

### Acceptance criteria
- [ ] Fresh launch → auth → lands directly on `ARDashboardRootView` (Explore tab).
- [ ] All 4 AR tabs load; viewer and create routes push correctly.
- [ ] Build has no references to parked non-AR screens; app compiles and runs on device.
- [ ] No regression in Nearby map.

---

## WS1 — Database migrations (foundation for everything)

**Goal:** All schema needed by WS2–WS7 exists and RPCs return the required columns.

### 1.1 Apply the pending AR dashboard migration (BLOCKER)

Run `supabase_ar_dashboard.sql` (repo root) in the Supabase SQL editor. It:
- Adds `locations.altitude_m`, `locations.altitude_accuracy_m`.
- Adds `digital_assets.animation_name`, `animation_index`, `trigger_type` (CHECK in `tap|proximity|speech|shake`), `trigger_config jsonb`.
- Creates `asset_views(user_id, asset_id FK→digital_assets ON DELETE CASCADE, seen_at)` + index.
- Requires **DROP + re-CREATE** of `get_nearby_assets_full(double precision,double precision,double precision)` to append to BOTH the `RETURNS TABLE` and the `SELECT`: `l.address, l.altitude_m, da.animation_name, da.animation_index, da.trigger_type, da.trigger_config`. First dump the current def with `pg_get_functiondef` to preserve offer subqueries/visibility filters.

**Verification:** after running, call the RPC from the SQL editor with a known lat/lon and confirm the 6 columns come back; then confirm the app's viewer loads assets without decode errors.

### 1.2 Rotation quaternion columns (for WS2)

```sql
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS rot_qx double precision,
  ADD COLUMN IF NOT EXISTS rot_qy double precision,
  ADD COLUMN IF NOT EXISTS rot_qz double precision,
  ADD COLUMN IF NOT EXISTS rot_qw double precision,
  -- heading accuracy captured at placement, degrees; NULL = unknown/legacy
  ADD COLUMN IF NOT EXISTS heading_accuracy_deg double precision;
```
Add these to the `get_nearby_assets_full` RETURNS TABLE + SELECT (`da.rot_qx, ...`). All nullable → legacy rows and the old Euler columns keep working (WS2 falls back to Euler when quaternion is NULL).

### 1.3 Follow graph (for WS4)

```sql
CREATE TABLE IF NOT EXISTS public.follows (
  follower_id  uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, following_id),
  CHECK (follower_id <> following_id)
);
CREATE INDEX IF NOT EXISTS follows_following_idx ON public.follows(following_id);
CREATE INDEX IF NOT EXISTS follows_follower_idx  ON public.follows(follower_id);

-- RLS
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY follows_select_all ON public.follows FOR SELECT USING (true);
CREATE POLICY follows_insert_self ON public.follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);
CREATE POLICY follows_delete_self ON public.follows FOR DELETE
  USING (auth.uid() = follower_id);

-- Counts helper (used by profiles)
CREATE OR REPLACE FUNCTION public.get_follow_counts(p_user uuid)
RETURNS TABLE(followers bigint, following bigint) LANGUAGE sql STABLE AS $$
  SELECT
    (SELECT count(*) FROM follows WHERE following_id = p_user),
    (SELECT count(*) FROM follows WHERE follower_id  = p_user);
$$;
```

### 1.4 User public key for E2E chat (for WS6)

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS x25519_public_key text,   -- base64 raw 32-byte Curve25519 KA public key
  ADD COLUMN IF NOT EXISTS key_updated_at timestamptz;
```
RLS: users may update only their own row; public key is readable by all authenticated users (needed to encrypt to them).

### 1.5 Asset engagement (optional but recommended for real recommendations, WS5)

If hype/comments on assets are in scope:
```sql
CREATE TABLE IF NOT EXISTS public.asset_hype (
  user_id uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  asset_id uuid NOT NULL REFERENCES public.digital_assets(asset_id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, asset_id)
);
```
`digital_assets.hype_count`/`view_count` already exist and feed `engagementScore`.

### 1.6 pgvector: embeddings for deep search & recommendations (for WS5)

**Decision: pgvector hybrid** — semantic discovery lives in Supabase Postgres, not a separate search service. Plain weighted-SQL scoring is arithmetic and shallow (can't understand "cyberpunk dragon" or find *similar-vibe* assets); embeddings + vector ANN make search and recs semantic. Because Locolo is location-bound, a **PostGIS geo pre-filter keeps the candidate set tiny**, so vector search stays fast without an external ANN service.

```sql
-- Enable once per project.
CREATE EXTENSION IF NOT EXISTS vector;

-- Per-asset embedding. Dimension must match the chosen embedding model
-- (e.g. 768 or 1536). Store an embedding of name + description (+ optional
-- rendered-thumbnail image embedding as a second column if using multimodal).
ALTER TABLE public.digital_assets
  ADD COLUMN IF NOT EXISTS embedding vector(1536),
  ADD COLUMN IF NOT EXISTS embedding_model text,       -- provenance / re-embed control
  -- Postgres full-text fallback for exact keyword/name search:
  ADD COLUMN IF NOT EXISTS search_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,''))) STORED;

CREATE INDEX IF NOT EXISTS digital_assets_embedding_idx
  ON public.digital_assets USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS digital_assets_tsv_idx
  ON public.digital_assets USING gin (search_tsv);

-- Per-user preference vector = rolling average of embeddings of assets the
-- user has Explored/hyped. Recomputed on interaction (Edge Function or trigger).
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS taste_embedding vector(1536),
  ADD COLUMN IF NOT EXISTS taste_updated_at timestamptz;
```

**Embedding generation (the one real new dependency):** a **Supabase Edge Function** triggered on `digital_assets` insert/update calls an embedding model (text of name+description; hand-drawn assets from WS7 embed their name/description or a rendered thumbnail) and writes `embedding` + `embedding_model`. A second function recomputes a user's `taste_embedding` when they hype/explore an asset. Backfill existing rows once. **Model choice is deferred to WS5** but the vector **dimension must be fixed before creating the column.**

**Hybrid discovery RPC** (semantic For You + free-text search share one function):
```sql
CREATE OR REPLACE FUNCTION public.get_recommended_assets(
  p_user uuid,
  p_lat  double precision,
  p_lon  double precision,
  p_radius_meters double precision DEFAULT 50000,
  p_query_embedding vector(1536) DEFAULT NULL,   -- set for text search; NULL = personalized feed
  p_limit int DEFAULT 60
) RETURNS TABLE (/* identical column list to get_nearby_assets_full */) ...
```
Ranking inside the RPC:
1. **Geo pre-filter** with PostGIS (`ST_DWithin` within `p_radius_meters`) — hard gate, shrinks the set.
2. **Semantic distance** = `embedding <=> coalesce(p_query_embedding, (SELECT taste_embedding FROM users WHERE user_id = p_user))`. If both are NULL (cold-start user, no query), skip this term.
3. **Final score** = `0.45*(1 - semantic_distance) + 0.20*engagement_norm + 0.20*proximity_norm + 0.15*recency_norm + follow_boost`, `ORDER BY score DESC LIMIT p_limit`.

Returns the SAME column set as `get_nearby_assets_full` so `DigitalAsset` decodes unchanged.

### Acceptance criteria
- [ ] `supabase_ar_dashboard.sql` applied; RPC returns all columns; viewer decodes cleanly.
- [ ] Quaternion + heading columns exist and are in the RPC.
- [ ] `follows` + RLS + `get_follow_counts` created.
- [ ] `users.x25519_public_key` exists with correct RLS.
- [ ] (If in scope) `asset_hype` + `get_recommended_assets` created.

---

## WS2 — AR accuracy & rotation fix (quaternion + north-aligned frame)

**Goal:** An asset is replayed at the **same real-world orientation** the creator gave it, across devices and sessions. Fixes the current bug where yaw ("which way it faces") is effectively random.

**Why (verified bug):**
- Capture (`ARPlacementView.makeUIView`): session uses `ARWorldTrackingConfiguration` with **default `.gravity`** alignment (never sets `worldAlignment`). Model is a child of `AnchorEntity(plane: .horizontal)`. `Coordinator.confirm` saves `entity.transform` → `ARCreateViewModel.setPlacement`.
- Store (`ARCreateViewModel.saveAsset`): `transformValue.rotation.toEulerAngles()` (custom XYZ decomposition) → `rotation_x/y/z` degrees.
- Replay (`ARDisplayViewModel.applyStoredTransform`): rebuilds `rotZ * rotY * rotX` and sets it as the entity's local rotation under a **north-aligned** anchor (`ARGeoAnchor` = ENU, or `.gravityAndHeading` world where −Z = north).
- **Mismatch:** captured yaw is relative to an arbitrary plane/gravity frame; replayed yaw is interpreted relative to true north. Pitch/roll survive (both gravity-aligned); **yaw does not.** Plus Euler round-trip (quat→euler→quat) risks gimbal/order errors.

### Changes

1. **Align the creation session to north.** In `ARPlacementView.makeUIView`, set:
   ```swift
   config.worldAlignment = .gravityAndHeading   // -Z = true north, +X = east, +Y = up
   ```
   Keep `planeDetection = [.horizontal]`, keep `ARCoachingOverlayView`.

2. **Capture world-space orientation relative to north.** In `Coordinator.confirm`, instead of `entity.transform` (local to plane anchor), capture the entity's **world transform**:
   ```swift
   guard let entity = self.entity else { return }
   let worldRotation = entity.orientation(relativeTo: nil)   // simd_quatf in world (north-aligned) space
   let worldScale    = entity.scale(relativeTo: nil)
   vm.setPlacement(rotationWorld: worldRotation, scale: worldScale, headingAccuracy: currentHeadingAccuracy)
   ```
   Because the session is now `.gravityAndHeading`, `worldRotation` is expressed relative to true north — the invariant we need.

3. **Store the quaternion.** Change `ARCreateViewModel.setPlacement` + `saveAsset`:
   - New signature `setPlacement(rotationWorld: simd_quatf, scale: SIMD3<Float>, headingAccuracy: Double)`.
   - Persist `rot_qx=q.imag.x, rot_qy=q.imag.y, rot_qz=q.imag.z, rot_qw=q.real`, `scale_x/y/z` as today, and `heading_accuracy_deg`.
   - **Keep writing the Euler `rotation_x/y/z`** too (from the same quaternion via `toEulerAngles`) for backward-compat with any old readers. Extend `NewAsset` with the 4 quaternion fields + `heading_accuracy_deg`.

4. **Replay from quaternion.** In `ARDisplayViewModel.applyStoredTransform`:
   ```swift
   if let qx = asset.rotQX, let qy = asset.rotQY, let qz = asset.rotQZ, let qw = asset.rotQW {
       entity.orientation = simd_quatf(ix: Float(qx), iy: Float(qy), iz: Float(qz), r: Float(qw))
   } else {
       // legacy Euler fallback (existing rotZ*rotY*rotX code)
   }
   ```
   Because both geo (`ARGeoAnchor`, ENU) and world (`.gravityAndHeading`) anchors are north-aligned, the stored world-relative quaternion reproduces the true facing direction in both modes.

5. **Add fields to `DigitalAsset.swift`** (all optional): `rotQX/rotQY/rotQZ/rotQW`, `headingAccuracyDeg`, with `CodingKeys` `rot_qx/rot_qy/rot_qz/rot_qw/heading_accuracy_deg`. **These must be present in the RPC (WS1.2).**

6. **Heading-accuracy gate at capture.** Start heading updates (`locationManager.startUpdatingHeading()`), read `heading.headingAccuracy`. If `< 0` (invalid) or `> 20°`, block the long-press confirm and show "Calibrate compass — figure-8 your phone." Store the accuracy so the viewer can down-rank/soft-warn assets captured with poor heading.

7. **Translation gesture mismatch (fix UX honesty).** `installGestures([.translation, .rotation, .scale])` lets the user drag the model, but final position is the raw GPS point (translation discarded). Either (a) remove `.translation` from the gesture set so users can't move what won't be saved, or (b) capture the horizontal offset and add it to the placement (advanced). **Recommended for release: remove `.translation`.**

### Acceptance criteria
- [ ] Place an asset facing a landmark; reopen the viewer in a fresh session (and on a second device) → asset faces the same real-world direction.
- [ ] Assets with only legacy Euler data still render (fallback path).
- [ ] Placement is blocked with a clear message when compass accuracy is poor.
- [ ] Scale reproduces correctly.

---

## WS3 — Localization resilience & fallbacks

**Goal:** The viewer never strands the user on an empty camera; every failure mode has a message and a recovery.

**Why:** Current fallback spine is good (geo→world with 25 s timeout in `armGeoFallback`; mid-session `.notAvailable` → world). Gaps below.

### Changes (all in `ARDisplayViewModel` / `ARDisplayView`)

1. **Coaching overlay in the viewer.** Add `ARCoachingOverlayView` (goal `.tracking` for world mode) in `ARViewContainer.makeUIView`, mirroring `ARPlacementView`. Biggest single UX win for world-tracking init.

2. **Handle interruptions & limited tracking.** Implement:
   - `session(_:cameraDidChangeTrackingState:)` → surface `.limited(.excessiveMotion)` ("Slow down"), `.limited(.insufficientFeatures)` ("Point at a textured surface"), `.limited(.initializing)`, `.limited(.relocalizing)`.
   - `sessionWasInterrupted` / `sessionInterruptionEnded` → status + auto re-run config on resume.

3. **Permission-denied recovery.** In `startLocationUpdates` `.denied/.restricted` and on camera denial: show a button that opens `UIApplication.openSettingsURLString`, plus a Retry.

4. **No-GPS-fix recovery.** If no `CLLocation` arrives within ~10 s, show Retry and fall back to `locationManager.location` (last known) if available.

5. **Manual mode toggle.** Add a small control to force GPS mode when geo localizes poorly (calls `startWorldTrackingSession()`), and to retry geo.

6. **Re-fetch as the user walks.** `fetchNearbyAssets` currently runs once at localization; `placedIds` blocks re-placement. Add: on `didUpdateLocations`, if the user moved > ~75 m from the last fetch origin, re-run `fetchNearbyAssets` and place only assets whose id isn't in `placedIds`. Cap total placed entities (e.g. 40) and cull the farthest when exceeding.

7. **Fix the cancellables race (also perf, see WS8).** `loadModel` stores its Combine subscription in the shared `cancellables`, which `startWorldTrackingSession`/`startGeoTrackingSession` clear via `cancellables.removeAll()`. A geo→world fallback mid-download cancels in-flight loads. Use a dedicated `private var modelLoadTokens = Set<AnyCancellable>()` that is NOT cleared on mode switch, or switch to `async` `Entity(contentsOf:)` with structured `Task`s keyed by asset id.

### Acceptance criteria
- [ ] Coaching overlay appears during world init and dismisses when tracking is normal.
- [ ] Each tracking-limited reason shows a distinct, actionable hint.
- [ ] Denied camera/location shows an "Open Settings" path, not a dead end.
- [ ] Walking 100 m loads newly-nearby assets without a session restart.
- [ ] Switching geo→world mid-download does not cancel model loads.

---

## WS4 — Social layer: follow graph, profiles, recommendations

**Goal:** The core "Instagram for real life" loop: view a creator's profile, follow them, and have follows influence the feed.

**Why:** **No follow/friend graph exists today.** `User.stats` holds display counts but there's no relationships table, follow button, or follower lists. `ARCreatorDashboardView` is the *owner's* analytics dashboard, not a public profile. `UserProfileView` exists in the main app but isn't wired into the AR module.

### 4.1 Follow repository + view model

Create `Locolo/ARModule/Services/FollowRepository.swift`:
```swift
final class FollowRepository {
    private let client = SupabaseManager.shared.client
    func follow(_ target: UUID, from me: UUID) async throws          // insert
    func unfollow(_ target: UUID, from me: UUID) async throws        // delete
    func isFollowing(_ target: UUID, from me: UUID) async throws -> Bool
    func counts(for user: UUID) async throws -> (followers: Int, following: Int)   // get_follow_counts RPC
    func followers(of user: UUID) async throws -> [ARCreator]
    func following(of user: UUID) async throws -> [ARCreator]
}
```
Reuse the `ARCreator` struct already defined in `ARExploreViewModel.swift` (move it to its own file `Models/ARCreator.swift` so profiles + explore share it).

### 4.2 Public profile screen

Create `Locolo/ARModule/Dashboard/CreatorProfileView.swift` + `CreatorProfileViewModel.swift`:
- Header: avatar, name, username, verified badge, bio, follower/following counts, **Follow/Unfollow** button, **Message** button (WS6).
- Content: the creator's public assets as a grid (reuse `ArtworkCard`/`ARSocialAssetCard`) and a small map of where they've placed assets.
- Tapping an asset → `AssetDetailSheet` / open-in-AR.
- Add `ARRoute.profile(userId: UUID)` to `ARDashboardState`/`ARDashboardRootView.destination(for:)`.

### 4.3 Wire creators into the feed

In `ARSocialAssetCard` and `AssetDetailSheet`, make the creator chip tappable → push `ARRoute.profile(creator.id)`. `ARExploreViewModel.creator(for:)` already provides the `ARCreator`.

### 4.4 Followers/following lists

`FollowListView.swift` (segmented followers/following) reachable from the profile counts.

### Acceptance criteria
- [ ] Tapping a creator anywhere opens their public profile.
- [ ] Follow/unfollow persists and updates counts immediately (optimistic) and after refetch.
- [ ] A user cannot follow themselves (DB CHECK + UI hides the button).
- [ ] Follower/following lists load and link to profiles.

---

## WS5 — Explore, deep search & recommendations (pgvector hybrid)

**Goal:** Semantic personalized feed + deep (semantic) search over assets, all in Supabase via pgvector. Replaces the trivial client-side sorts.

**Why:** `ARExploreViewModel.feedAssets` is: For You = newest, Trending = `engagementScore`, Nearby = distance. No personalization, no semantics. `ARSearchView` (on `ARGalleryViewModel`) is keyword-only. Arithmetic SQL scoring can't understand meaning or similarity.

### 5.1 Embedding pipeline (depends on WS1.6)
1. **Pick the embedding model + fix the vector dimension** before creating the pgvector columns (768 vs 1536, text-only vs multimodal). Document the model in `embedding_model`.
2. **Supabase Edge Function `embed-asset`** — on `digital_assets` insert/update, embed `name + description` (WS7 hand-drawn assets included; optionally embed a rendered thumbnail with a multimodal model) → write `embedding`.
3. **Edge Function `update-taste`** — when a user hypes/Explores an asset, fold that asset's embedding into `users.taste_embedding` (rolling mean) → personalization signal.
4. **One-time backfill** of `embedding` for existing assets.

### 5.2 For You → semantic server ranking
Call `get_recommended_assets(p_user, p_lat, p_lon, p_radius_meters)` with `p_query_embedding = NULL` (uses the user's `taste_embedding`). Cold-start (no taste vector yet) → RPC falls back to the engagement/proximity/recency terms. Keep client paging (`visibleCount`) and Trending/Nearby as honest non-semantic sorts.

### 5.3 Deep semantic search (upgrade `ARSearchView`)
- Free-text query → embed the query string (client calls an `embed-query` Edge Function, or a lightweight endpoint) → call `get_recommended_assets(..., p_query_embedding: <vec>)` for semantic results.
- **Hybrid:** run the vector search AND the Postgres full-text (`search_tsv @@ plainto_tsquery(...)`) path; merge/dedupe so exact name matches always surface alongside semantic matches (reciprocal-rank fusion or simple union with FTS boosted).
- Keep recent searches (`@AppStorage("ar_recent_searches")`) and category chips.

### 5.4 Asset engagement (needs WS1.5)
Add hype toggle + count and comments to `AssetDetailSheet` (comments reuse the Echo pattern, scoped to `asset_id`). Hype/Explore events feed `update-taste` (5.1.3).

### 5.5 States
Empty/loading/error states + pull-to-refresh for feed and search.

### Acceptance criteria
- [ ] Searching a *concept* (not an exact name) returns semantically relevant assets; exact-name search still hits via FTS.
- [ ] For You differs per user and reflects taste (Explored/hyped) + follows + proximity + freshness.
- [ ] Embedding is generated automatically on asset create (incl. hand-drawn); backfill done.
- [ ] Cold-start users get a sensible non-empty feed.
- [ ] Feed/search handle empty/error; pull-to-refresh works.
- [ ] (If in scope) hype/comment persists and updates counts + taste vector.

---

## WS6 — End-to-end encrypted chat, moved into the AR app

**Goal:** Messages are **E2E encrypted** (server stores ciphertext only), sender identity can't be spoofed, and chat is reachable from inside the AR app.

**Why (verified):** Firestore messages are plaintext; participant filtering is client-side; there are no security rules; Firebase auth is **anonymous** so the claimed `senderId` (a Supabase UUID) has no cryptographic binding — anyone can send as anyone and, without rules, read anything.

### 6.1 Crypto design (CryptoKit)

- **Identity keys:** on first run, generate a **Curve25519.KeyAgreement** private key. Store the raw private key in the **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Publish the base64 raw public key to `users.x25519_public_key` (WS1.4) + `key_updated_at`.
- **Conversation key (1:1):** derive a shared secret with `privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)`, then `sharedSecret.hkdfDerivedSymmetricKey(using: SHA256, salt: <conversationId bytes>, sharedInfo: Data("locolo-chat-v1".utf8), outputByteCount: 32)`. Both participants derive the **same** `SymmetricKey`. Cache it in memory per conversation.
- **Per-message encryption:** `try AES.GCM.seal(plaintextData, using: key)`. Store `sealed.combined` (nonce‖ciphertext‖tag) base64 in the `text` field's place → rename Firestore field to `ciphertext`. Decrypt with `AES.GCM.open(.init(combined:), using: key)`.
- **`lastMessage` preview:** store `"🔒"` or a locally-cached decrypted preview keyed by conversationId in the Keychain/`UserDefaults` — never plaintext on the server.
- **Limitation to document:** static-key X25519 + AES-GCM gives confidentiality + integrity but **no forward secrecy**. Stretch goal: Double Ratchet (Signal-style) if key compromise resistance is required. Ship static-key for v1.
- **Key change / trust:** if `key_updated_at` changes for a peer, show a "safety number changed" notice (prevents silent key swaps). Optional displayable safety number = SHA256 of sorted public keys.

### 6.2 Identity binding (stop spoofing)

Choose one:
- **(A) Recommended given existing Supabase auth — migrate chat to Supabase Realtime + RLS.** Messages/conversations become Postgres tables; `auth.uid()` binds the sender; RLS restricts read/write to participants. This *also* removes the anonymous-Firebase problem and unifies auth. Larger change but structurally correct. Store ciphertext columns.
- **(B) Keep Firestore + custom-token binding + security rules.** Replace `Auth.auth().signInAnonymously()` in `ContentView` with a **Firebase custom token minted by a trusted backend from the verified Supabase session** (so `request.auth.uid` == Supabase user id). Then add Firestore rules:
  ```
  match /conversations/{cid} {
    allow read, update: if request.auth.uid in resource.data.participants;
    allow create: if request.auth.uid in request.resource.data.participants;
    match /messages/{mid} {
      allow read: if request.auth.uid in get(/databases/$(db)/documents/conversations/$(cid)).data.participants;
      allow create: if request.auth.uid == request.resource.data.senderId
                    && request.auth.uid in get(...).data.participants;
    }
  }
  ```
**Decision:** if time permits, (A); otherwise (B). Both are acceptable **only with E2E on top** (transport becomes ciphertext-only either way).

### 6.3 Code changes
- `MessagingModels.swift`: `Message.text` → `Message.ciphertext: String`; add non-persisted `decryptedText: String?` populated after `AES.GCM.open`. `Conversation.lastMessage` becomes ciphertext or an opaque preview.
- `ChatRepository.sendMessage`: encrypt before write. `listenMessages`: decrypt each doc after fetch (drop/mark undecryptable ones). Keep the existing `deletedUpTo`/`deletedBy` soft-delete logic.
- New `Locolo/ARModule/Services/CryptoService.swift`: key generation, Keychain storage, public-key publish/fetch, conversation-key derivation, seal/open helpers.
- New `Locolo/ARModule/Services/KeyDirectory.swift`: fetch/cache peers' public keys from `users`.

### 6.4 Move chat into AR
- Add a **Messages entry** in the AR shell: a header icon in `ARExploreView`/profile, or a 5th `ARTab`. Route `ARRoute.conversations` → `ConversationListView`; `ARRoute.chat(conversationId, peerId)` → `ChatView`. Reuse existing `Views/Messages/` screens (bring them into target).
- **Message** button on `CreatorProfileView` (WS4) → find-or-create conversation (`ChatRepository.findExistingConversation`/`createConversation`) → push chat.

### 6.5 Text search in chat (E2E-compatible)

**Hard constraint:** because messages are E2E encrypted, the **server only holds ciphertext — you cannot search it server-side** (no `WHERE text ILIKE ...`, no FTS on the backend). Search must run over **locally-decrypted** messages on-device. Design:

1. **Local encrypted index.** Maintain an on-device store of decrypted messages — reuse the existing CoreData stack (`Models/Cache/`) or add a dedicated **SQLite FTS5** table (`message_fts(conversation_id, message_id, sender_id, body, ts)`). Populate it as `ChatRepository.listenMessages` decrypts each message (write plaintext to the local index only; it never leaves the device). Protect the on-disk DB with iOS Data Protection (`.completeUntilFirstUserAuthentication`) or an app-level key in Keychain.
2. **Search UX.** Two scopes: **in-conversation search** (filter the open thread) and **global search** (across all conversations). Both query the local index:
   - FTS5: `SELECT ... FROM message_fts WHERE message_fts MATCH ? ORDER BY ts DESC` (typo-tolerant enough with `prefix`/`porter` tokenizer).
   - Or, if staying in CoreData, an in-memory/`NSPredicate CONTAINS[cd]` filter over the cached decrypted messages (fine at small scale).
3. **Result → jump.** Tapping a hit opens the conversation scrolled to that message (highlight). Global results group by conversation with a snippet + timestamp.
4. **New-message indexing.** Each newly-decrypted incoming/outgoing message is inserted into the index in real time so search stays current.
5. **Privacy/lifecycle.** Wipe the local index on logout and on "delete conversation" (respect the existing `deletedUpTo`/`deletedBy` semantics — don't index or return messages the user soft-deleted). Never sync the plaintext index anywhere.

**New file:** `Locolo/ARModule/Services/ChatSearchIndex.swift` (FTS5 wrapper: `index(_:)`, `remove(conversationId:)`, `search(_:scope:)`, `wipe()`). Wire it into `ChatRepository`/`ChatViewModel` at the decrypt site.

**Optional (server-assisted, document as a non-default alternative):** *blind indexing* — store per-token HMACs (keyed with a client secret) alongside ciphertext so the server can match exact tokens without seeing plaintext. It enables server-side exact-term search but **leaks token frequency/patterns**, breaks on typos/substrings, and adds complexity. Not recommended for v1; the local FTS index is simpler and strictly more private.

### Acceptance criteria
- [ ] Message stored server-side is unreadable ciphertext; two devices exchange messages and both decrypt correctly.
- [ ] A user cannot read a conversation they aren't a participant of (verified against the backend, not just UI).
- [ ] Sender identity is bound (spoofing a `senderId` is rejected).
- [ ] Chat is reachable from inside the AR app and from a creator's profile.
- [ ] Peer key-change surfaces a warning.
- [ ] **In-conversation and global text search return matches from the local index; tapping a result jumps to the message.**
- [ ] **Search never hits the server for plaintext; the local index is wiped on logout and excludes soft-deleted messages.**

---

## WS7 — Hand-gesture air-drawing → post & share

**Goal:** A user draws in 3D space with a **hand-gesture (pinch-to-draw)** in AR, the strokes become a real 3D model, and it's posted to Locolo AR (placed at their location) **and shared** in one flow.

**Platform reality (important):** iPhone/iPad ARKit has **no native world-space hand skeleton** (that's visionOS). On iOS the robust path is **Vision `VNDetectHumanHandPoseRequest`** run on the AR camera frames to track the index fingertip + detect a thumb–index **pinch**, then project that 2D point to a 3D point at a fixed depth in front of the camera. Provide a **touch-drawing fallback** (drag on screen → project onto a plane / fixed depth) for reliability and accessibility. Ship both; default to hand-tracking with a toggle.

### 7.1 New module: `Locolo/ARModule/Draw/`

- `ARDrawView.swift` (`UIViewRepresentable`) + `ARDrawViewModel.swift`.
- `HandTracker.swift` — wraps `VNDetectHumanHandPoseRequest` (`maximumHandCount = 1`).
- `StrokeBuilder.swift` — point smoothing + tube-mesh generation.
- `USDZExporter.swift` — ModelIO export of the generated mesh to a `.usdz` file.

### 7.2 Hand tracking + pinch (algorithm)

1. Session: `ARWorldTrackingConfiguration`, `.gravityAndHeading` (so the exported model + placement share the north frame from WS2).
2. On `session(_:didUpdate frame:)` (throttled, e.g. every 2nd frame): run Vision on `frame.capturedImage`:
   ```
   request = VNDetectHumanHandPoseRequest(); request.maximumHandCount = 1
   handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage,
                                   orientation: .right)   // match device orientation
   try handler.perform([request])
   guard let hand = request.results?.first else { drop stroke }
   let idx = try hand.recognizedPoint(.indexTip)
   let thm = try hand.recognizedPoint(.thumbTip)
   guard idx.confidence > 0.3, thm.confidence > 0.3 else { continue }
   pinchDist = distance(idx.location, thm.location)   // normalized image coords
   isPinching = pinchDist < PINCH_ON_THRESHOLD (hysteresis: off > PINCH_OFF_THRESHOLD)
   ```
3. Map Vision's normalized point (origin bottom-left) to view/screen coords, accounting for orientation and the `displayTransform` of the frame. Then get a **3D point at fixed depth** `D` (e.g. 0.4 m) in front of the camera: build a ray with `arView.ray(through: screenPoint)` and take `origin + direction * D`, OR unproject. (Fixed depth is more stable than raycasting to planes for air-drawing.)
4. **Pinch state machine:** transition to pinching → **begin stroke**; while pinching → append points (min spacing ~0.5 cm to limit density); release → **end stroke**.

### 7.3 Stroke → mesh (algorithm)

- Smooth raw points with a moving average / Catmull-Rom resample to uniform spacing.
- Generate a **tube**: for each centerline point, build a ring of `N` (e.g. 6–8) vertices in the plane perpendicular to the local tangent (use a stable reference-frame/parallel-transport to avoid twisting); connect consecutive rings with triangles; cap the ends. Radius = configurable stroke width.
- Build a `MeshResource` via `MeshDescriptor` (positions, normals, primitives) for live preview in RealityKit; apply an unlit or emissive `UnlitMaterial`/`SimpleMaterial` in the chosen color.
- Support multiple strokes (each pinch = one stroke); accumulate into one parent `Entity`.
- Live preview: add/update the entity in the `ARView` scene as the user draws; show a color/width palette and Undo (pop last stroke).

### 7.4 Export → post (reuse existing pipeline)

- On **Finish**: merge all stroke meshes into one, convert to a ModelIO `MDLAsset`:
  - Build `MDLMesh` from the combined vertex/normal/index buffers (or load the RealityKit-generated geometry into ModelIO). Add to `MDLAsset`, then `asset.export(to: usdzURL)` (ModelIO supports `.usdz` export). Validate the file loads back via `Entity(contentsOf:)`.
- Hand the exported local `.usdz` URL into the **existing creation flow**: set it as `ARCreateViewModel.localFileURL`, run `uploadPickedFileToStorage()`, then `saveAsset(userId:)`. This gives the drawing the full asset treatment (location, address, altitude, quaternion orientation from WS2, visibility, triggers) for free.
- **"Share at the same time":** after `saveAsset` succeeds, (a) if follow-graph exists, it appears in followers' For You automatically; (b) present the iOS **share sheet** with a deep link to the asset (`locolo://asset/<asset_id>` — register a URL scheme) and/or a rendered thumbnail; (c) optionally auto-post to the user's profile grid (it already is, as a `digital_asset`).

### 7.5 Entry point
- Add a **Draw** action to the create menu (alongside "Upload model") in `ARCreateAssetFlowView` / the create route, and/or a prominent button on Explore.

### 7.6 Fallbacks & guardrails
- Hand not detected / low light → auto-suggest **touch-drawing** mode.
- Cap total points/strokes to keep the exported USDZ small (< a few MB); warn near the cap.
- Simulator-guard the AR/Vision code (`#if targetEnvironment(simulator)`).
- Camera permission already required; Vision needs no extra permission.

### Acceptance criteria
- [ ] Pinching starts/stops a stroke; releasing ends it; strokes appear live in AR.
- [ ] Touch-drawing fallback works when hands aren't detected.
- [ ] Finishing exports a valid USDZ that reloads and renders.
- [ ] The drawing posts as a normal asset (placed at the user's location with correct orientation) and is discoverable in the viewer + feed.
- [ ] Share sheet presents a working deep link to the posted asset.

---

## WS8 — Model caching & performance

**Goal:** Fast, low-data asset loading in the viewer.

**Why:** `ARDisplayViewModel.loadModel` downloads the USDZ via `URLSession` on **every** placement and never uses the existing `MediaCache` (`Models/Cache/MediaCache.swift`).

### Changes
1. Route USDZ downloads through `MediaCache` (cache by remote URL; reuse the local file if present). Same for WS7 exports if re-fetched.
2. Deduplicate concurrent downloads of the same URL.
3. Combine with the WS3.7 cancellables fix (don't cancel in-flight loads on mode switch).
4. Cap concurrently-loaded entities and cull the farthest beyond a limit.

### Acceptance criteria
- [ ] Re-entering the viewer near the same assets loads them from cache (no re-download).
- [ ] Memory stays bounded when many assets are nearby.

---

## WS9 — Cross-cutting & release checklist

**Privacy & permissions:** confirm `INFOPLIST_KEY_NSCameraUsageDescription`, `...NSLocationWhenInUseUsageDescription`, `...NSMicrophoneUsageDescription` (speech triggers), and `...NSSpeechRecognitionUsageDescription` are set in `project.pbxproj`. Add a coarse/opt-in location story if profiles surface location. Add a privacy note that chat is E2E encrypted.

**Auth:** ensure the standalone app's auth (`AuthStartView` flow) works end-to-end and that the WS6 identity binding replaces anonymous Firebase auth (or the custom-token path is in place).

**Analytics/telemetry (optional):** log geo-vs-world mode usage, localization failures, model load failures — to tune WS2/WS3.

**Release gate:**
- [ ] WS1 migration applied and verified in production Supabase.
- [ ] Viewer decodes assets with the new RPC columns (no decode failures in logs).
- [ ] Rotation reproduces across devices (WS2).
- [ ] Localization fallbacks verified on a real device in a non-geo-mapped area (WS3).
- [ ] Follow + profiles working (WS4); For You personalized (WS5).
- [ ] Chat E2E verified (WS6): ciphertext at rest, cross-device decrypt, non-participant denied.
- [ ] Hand-draw posts a valid, discoverable asset + share link (WS7).
- [ ] No references to parked non-AR code; app boots AR-only (WS0).
- [ ] Tested on a physical device (AR is device-only).

---

## Appendix A — File map (new files to create)

```
Locolo/ARModule/ARAppRootView.swift                    # WS0
Locolo/Models/ARCreator.swift                          # WS4 (move struct out of ARExploreViewModel)
Locolo/ARModule/Services/FollowRepository.swift        # WS4
Locolo/ARModule/Dashboard/CreatorProfileView.swift     # WS4
Locolo/ARModule/ViewModels/CreatorProfileViewModel.swift  # WS4
Locolo/ARModule/Dashboard/FollowListView.swift         # WS4
Locolo/ARModule/Services/CryptoService.swift           # WS6
Locolo/ARModule/Services/KeyDirectory.swift            # WS6
Locolo/ARModule/Services/ChatSearchIndex.swift         # WS6.5 (local FTS5 over decrypted messages)
supabase/functions/embed-asset/                        # WS5.1 embedding on asset create
supabase/functions/update-taste/                       # WS5.1 user taste vector
supabase/functions/embed-query/                        # WS5.3 embed search query
Locolo/ARModule/Draw/ARDrawView.swift                  # WS7
Locolo/ARModule/Draw/ARDrawViewModel.swift             # WS7
Locolo/ARModule/Draw/HandTracker.swift                 # WS7
Locolo/ARModule/Draw/StrokeBuilder.swift               # WS7
Locolo/ARModule/Draw/USDZExporter.swift                # WS7
docs/migrations/2026_ar_release.sql                    # WS1 (all DDL consolidated)
```

## Appendix B — Files to edit

```
Locolo/ContentView.swift                 # WS0 root routing; WS6 auth binding
Locolo/LocoloApp.swift                   # WS0 trim environment objects
Locolo/Models/DigitalAsset.swift         # WS2 quaternion + heading fields
Locolo/ARModule/Creation/ARPlacementView.swift      # WS2 gravityAndHeading, world-space capture, remove .translation
Locolo/ARModule/Creation/ARCreateViewModel.swift    # WS2 setPlacement/saveAsset/NewAsset quaternion
Locolo/ARModule/Viewer/ARDisplayView.swift          # WS3 coaching overlay
Locolo/ARModule/Viewer/ARDisplayViewModel.swift     # WS2 replay, WS3 resilience/re-fetch, WS8 caching
Locolo/ARModule/ViewModels/ARExploreViewModel.swift # WS5 recommendation RPC; WS4 move ARCreator out
Locolo/ARModule/Dashboard/ARSocialAssetCard.swift   # WS4 tappable creator
Locolo/ARModule/Dashboard/AssetDetailSheet.swift    # WS4 creator link, WS5 hype/comments
Locolo/ARModule/ARDashboardState.swift              # WS4/6 new ARRoute cases
Locolo/ARModule/ARDashboardRootView.swift           # WS4/6 route destinations
Locolo/Models/MessagingModels.swift                 # WS6 ciphertext fields
Locolo/Models/Repositories/ChatRepository.swift     # WS6 encrypt/decrypt (or migrate to Supabase)
Locolo/ViewModels/ChatViewModel.swift               # WS6
Locolo/ARModule/Creation/ARCreateAssetFlowView.swift # WS7 Draw entry point
project.pbxproj                                      # WS0 bundle id/name; WS9 permission strings
```

## Appendix C — Open decisions locked for this build
- **Scope:** everything, including E2E chat.
- **Chat security:** full E2E now (CryptoKit static-key X25519 + AES-GCM), + identity binding (prefer migrating chat to Supabase Realtime + RLS; else Firebase custom token + security rules). No forward secrecy in v1 (Double Ratchet is a stretch goal).
- **Chat text search:** on-device only, over locally-decrypted messages (SQLite FTS5), since E2E means the server can't search ciphertext. Blind indexing is documented but rejected for v1.
- **Deep search & recommendations:** pgvector hybrid in Supabase — embeddings on assets + user taste vector + PostGIS geo pre-filter, one `get_recommended_assets` RPC serving both semantic feed and semantic search; Postgres FTS as exact-match fallback. Embedding generation via Supabase Edge Functions (model/dimension TBD, fixed before creating vector columns). No external search service.
- **Rotation:** quaternion stored relative to a north-aligned (`.gravityAndHeading`) frame, Euler kept as legacy fallback.
- **Hand-draw:** Vision pinch-tracking primary, touch-drawing fallback; export via ModelIO to USDZ and reuse the existing create/post pipeline; share via iOS share sheet + `locolo://asset/<id>` deep link.

*End of specification.*
