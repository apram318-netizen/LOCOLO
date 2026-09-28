# LOCOLO V2 — Social Depth & Gen-Z UI/UX

> Design spec. Builds on the shipped social layer (feed, comments, hype, follows, profiles, chat, activity, notifications — see `LOCOLO_AR_STATUS.md` §4.8). Extends `EngagementStore`/`ActivityStore`, the feed, and the design system in `ARDesign.swift` / `ARComponents.swift` / `ARSocialComponents.swift`. No chain dependency — ship in parallel with the marketplace.

---

## Part 1 — Social features (what makes it a *real* social network)

Ranked by retention impact × effort. Each notes the data/store it extends.

### Tier 1 — daily-return loops (build first)
1. **Stories / ephemeral drops.** 24h AR assets or snapshots that vanish; story ring on avatars (already have avatar UI). New `stories` table (author, media/asset, expires_at), viewed-state per user. Drives daily open.
2. **Full-screen vertical feed** ("For You" as a swipe-through, TikTok-style): one asset per screen — AR preview loop, creator, hype/comment/collect actions rail on the right, caption + place at the bottom, swipe up for next. This is the single biggest "feels like real social media" change. Keep the current card feed as an alternate "grid/list" view.
3. **Collections / Boards** (Pinterest-style): users curate assets into named, shareable, optionally collaborative boards ("Melbourne Street Art", "Want to collect"). New `collections` + `collection_items`. Wishlist becomes the default private board.
4. **Streaks & Explorer Passport gamification** (expand the existing Passport): daily-discovery streak with a flame, XP for placing/finding/collecting/trading, levels with unlock perks (profile flair, badges), weekly quests ("discover 3 assets in a new suburb"). All **off-chain** (no token). New `user_progress` (xp, level, streak, last_active), `quests`, `user_quests`, `achievements`.
5. **Leaderboards**: top explorers / creators / collectors, scoped by loop, city, following, or global; weekly resets keep it fresh. Feeds a competitive daily loop.

### Tier 2 — expression & graph density
6. **Reposts / "Re-drop"**: amplify someone's asset to your followers (with attribution) — the retweet primitive the feed currently lacks.
7. **Hashtags & topics**: `#cyberpunk`, `#sculpture`; tag on create, browse/search by tag, trending tags per area. New `tags` + `asset_tags`; extend search.
8. **Threaded comment replies** (currently @mention-flat): real reply trees + comment likes. Extend `asset_comments` with `parent_id`; add `comment_likes`.
9. **User tagging / collabs**: "featuring @maya" on an asset; collab drops credited to multiple creators (royalty split ties into the marketplace).
10. **Remixes**: place a new asset anchored to someone else's ("built on @sam's piece") — an AR-native duet. Provenance chain of remixes.
11. **Rich reactions**: beyond hype — a small emoji reaction set with burst animations (extends `EngagementStore`).

### Tier 3 — presence, events, community
12. **Live presence**: "3 explorers near this drop now" / "@maya is exploring nearby" (privacy-gated, opt-in, coarse). Ephemeral, via Realtime.
13. **AR events / meetups**: scheduled drops at a place+time ("Friday 6pm, Fed Square, 10 new pieces"); RSVP, reminders, event feed. Reuse the legacy `events` table concept, AR-native.
14. **Group chats & loop chats**: extend E2E chat to small groups (sender-keys / per-member wrapping — see Security); a chat per loop/community.
15. **Send an asset in DM**: share a collectible into a chat as a rich card (deep-links to the asset).
16. **Polls / questions on assets & stories**: lightweight engagement primitives.

### Moderation & control refinements (also Security)
- **Mute** (without block), **mute keywords/tags**, **restrict** (soft-block), **hide from map**.
- **Report appeals** + status visibility; creator "hide comment"/"pin comment"/"turn off comments".
- **Close friends / private drops** (visibility already supports public/friends/private — add a close-friends list).

### Notifications to add (extend the trigger + `send-push` + `ActivityStore` pattern — see Status §6 invariant 12)
`repost`, `collect` (someone added your asset to a board), `tag`/`mention-in-asset`, `remix`, `comment_reply`, `comment_like`, `story_view` (batched), `quest_complete`, `level_up`, `leaderboard_rank`, `event_reminder`, and the marketplace `sale`/`royalty`/`outbid`.

## Part 2 — Gen-Z design language

The current system (purple→pink→blue gradients, glass, rounded-heavy, dark-first, haptics) is a strong base. V2 pushes it from "clean & classy" to **"clean, classy, AND alive"** — expressive, tactile, motion-rich, without becoming noisy.

### Design principles
1. **Motion is meaning.** Spring physics on everything that moves (reuse `ARDesign.spring`); shared-element transitions between feed → detail → AR; parallax on scroll. Nothing snaps; everything eases.
2. **Tactile & rewarding.** Haptics on every meaningful action (extend `ARHaptics`); **celebrate wins** — confetti/particle burst on collect, sale, level-up, "you found it!"; animated number count-ups on stats and portfolio value.
3. **Bold, expressive, legible.** Big rounded display type for moments (values, names, milestones); generous negative space; high-contrast accents on deep dark. Maximalist highlights, minimalist canvas.
4. **Depth & material.** Layered glass, soft shadows, subtle noise/grain on backgrounds, gradient meshes behind hero moments, glow on active/gradient elements.
5. **Self-expression.** Profile themes (accent gradient picker), animated avatar rings (streak flame, verified shimmer, level color), asset "frames"/holo effects for rare pieces, custom bios with emoji.
6. **Playful voice.** Microcopy with personality ("You found it! 🔥", "Nobody's dropped here yet — be first", "Your bag is up 12% 📈"). Empty states are invitations, not dead ends (already started with `ARInlineEmptyState`).
7. **Ephemeral & authentic.** Stories, "exploring now" presence, time-limited drops — the BeReal/Snap energy that reads as "real people, right now."
8. **Accessibility is not optional.** Every color pair meets contrast in light + dark; full Dynamic Type; **Reduce Motion** disables count-ups/confetti/parallax; VoiceOver labels on all custom controls and charts. Fun must not exclude.

### New/upgraded components (extend `ARComponents.swift` / `ARSocialComponents.swift`)
- `ImmersiveFeedView` — full-screen vertical pager feed.
- `StoryRing` (animated gradient ring, viewed/unviewed states) + `StoryViewer`.
- `ReactionBurst` — particle burst for hype/collect/sale; `ConfettiView` for big wins.
- `StreakFlame`, `XPBar`, `LevelBadge`, `AchievementToast`.
- `AnimatedCounter` (spring count-up, Reduce-Motion aware) — used for hype, value, XP.
- `GradientMeshBackground` / `NoiseOverlay` for hero surfaces.
- `HoloCard` — holographic tilt/shimmer for rare or listed collectibles (gyroscope parallax).
- `SegmentedGlassPicker`, richer `ARFilterChip` with counts, `ShimmerSkeleton` (extend existing skeletons).
- `PortfolioValueHeader` — big animated value + range toggle (marketplace).
- Custom pull-to-refresh (branded orb) and a spring-loaded, haptic tab bar (extend the raised Create button).

### Per-screen refinement pass
- **Explore:** add the immersive full-screen feed mode toggle; story rail at top; trending tags row; "Creators to follow" already exists — add "Trending near you" and "Drops today". Bigger, bolder featured hero with holo treatment.
- **AR Viewer:** keep radar + hot/cold; add a subtle collect/hype gesture in-AR, a "rare find" flourish when discovering a listed/limited piece, and a share-to-story from a snapshot.
- **Profile:** themeable accent; featured/pinned assets; tabs (Created / Collected / Boards); level + streak + badges row; portfolio value (if public) ; holo frames on rare holdings.
- **Search:** tabs (Top / Assets / Creators / Tags / Places); trending tags; recent + suggested; semantic "Best matches" rail already there.
- **Chat:** reactions on messages, asset-share cards, typing/presence, group avatars; already E2E + styled.
- **Create:** more expressive stepper, drop-a-story option, tag/collab pickers, "list for sale?" step feeding the marketplace.
- **Activity:** grouped, animated, kind-badged (exists) — add level-up/quest/sale celebrations inline.
- **Onboarding:** interest picker (topics/tags) to seed For You; permissions explained with personality; the existing 3-page welcome → extend with an interests step.

### Motion/haptic budget (so it stays classy, not chaotic)
- Celebrations only on genuinely rewarding events (collect, sale, level-up, first-find) — never on routine taps.
- One hero animation per screen at a time; background effects are subtle (< 8% opacity noise, slow mesh drift).
- Everything gated by Reduce Motion; haptics respect the system setting.

## Part 3 — build order
1. Immersive vertical feed + stories + story rings (biggest "real social" jump).
2. Collections/Boards + reposts + hashtags (graph density & discovery).
3. Passport gamification (streaks/XP/levels/quests) + leaderboards (retention).
4. Threaded replies, reactions, remixes, tagging (expression).
5. Presence, events, group chat (community).
6. Design-system component upgrades land continuously alongside each feature.

Every feature reuses the shared stores (Status invariant 11) and adds notifications via the DB-trigger pattern (invariant 12). No feature ships without its empty/loading/error states and accessibility pass.
