# LOCOLO — AR Experience Polish & Feature Backlog

> Focused enhancement backlog for the **AR module specifically** — making what already exists look better, feel more premium ("more phone"), and function richer. Distinct from the big new pillars in `LOCOLO_V2_*` (marketplace/social/security). Non-AR screens stay in the app for now (per owner: separate them out closer to release).
> Reuses `TriggerEngine`, `ARMediaPlaybackController`, `SpeechTriggerService`, `ShakeDetector`, `ARDisplayViewModel`, `ARComponents.swift`, `ARDesign.swift`.

---

## What exists today (baseline)
- Viewer: geo + GPS-fallback placement, radar, hot/cold finder, snapshots, coaching overlay, re-anchoring, mode switch.
- **Interactions/triggers:** one trigger per asset — **tap / proximity / speech / shake / gaze / time-of-day / long-press / multi-tap / walk-around** — that fires the asset's **embedded USDZ animation** and plays **sidecar audio/video** (`ARMediaPlaybackController`; video supports texture plane).
- Creation: place with north-aligned quaternion, pick animation + trigger + media, hand-draw (tube/ribbon/neon brushes), live preview of animation/trigger.
- Share-in-chat ✅ (done — asset sends as an E2E rich card).
- AR clip → Story ✅ (`ARClipRecorder` + `StoryStore.postVideo`).
- Live Activity manager ✅ (`ExploringLiveActivity`); Widget Extension UI source ready (Xcode target still owner).

## Priorities at a glance
1. **Interaction & sensory richness** — largely shipped (see Suggested build order).
2. **Viewer visual polish** — discovery, rare-find, occlusion, lighting shipped.
3. **Creation flow polish** — live preview + brushes + placement shadow/true-size shipped; templates / multi-asset later.
4. **Instagram-parity AR social hooks** — boards/story/remix/deep-links shipped (SQL owner).
5. **"More phone" native touches** — Live Activity mgr shipped; Widget target + App Clip owner.

---

## 1. Interaction & sensory richness (build first)

The trigger system is the AR magic — deepen it.

- ✅ **Spatial/3D audio.**
- ✅ **Video-as-texture.**
- ✅ **Trigger → effect pairing.**
- ⏳ **Multi-step animation sequences.** (later — extend `trigger_config` with a sequence array)
- **More trigger types:**
  - ✅ Time-of-day, look-at / gaze, long-press, multi-tap, walk-around
  - ⏳ Weather (needs WeatherKit entitlement / partner API)
- ✅ **Reactions in AR.** (in-AR hype)
- ✅ **Ambient life.**
- ⏳ **Sound-reactive assets.** (`interaction_type = 'audio-reactive'` — later)

## 2. Viewer visual polish (make discovery magical)

- ✅ **Discovery reveal** + rare-find flourish
- ⏳ **Distance & depth cues** (partial — contact shadow on create; viewer halo later)
- ⏳ **Radar upgrade** (directional pulse / rarity colors — later)
- ⏳ **Onboarding-in-AR** ghost hand (later)
- ✅ **Occlusion & realism** (device-gated)
- ✅ **Lighting match**
- ✅ **Snapshot → Story** + **AR video clip → Story**

## 3. Creation flow polish

- ✅ **Live preview with real triggers.**
- ✅ **Placement finesse** — rotate/scale, contact shadow, true-size reset (snap-to-surface / undo later)
- ⏳ **Templates & effects** starter pack (later)
- ⏳ **Multi-asset scenes** (later)
- ✅ **Draw upgrades** — tube / ribbon / neon brushes (symmetry / draw-on-reveal later)
- ✅ **Caption/tag step** — hashtags, @collab, poll fields

## 4. Instagram-parity AR social hooks (beyond share-in-chat ✅)

- ✅ Save to Board / Collection (client; SQL §5.12)
- ✅ Presence / found-by surfaces (client; SQL §5.20)
- ✅ Remix (client; SQL §5.20)
- ✅ Story from discovery / clip
- ✅ Deep-link everything
- ✅ Tag people/places (collab + tags)

## 5. "More phone" — native premium touches

- ✅ **Haptics** on meaningful AR events
- ✅ **Live Activity** manager while exploring; ⏳ Widget Extension target in Xcode (`LocoloWidgets/`)
- ⏳ **App Clip** / home-screen "art near you" widget
- ⏳ Focus/Standby, Shortcuts/Siri
- ⏳ LOD / low-power mode beyond the 40-entity cap

---

## Suggested build order
1. ✅ **Spatial audio + video-as-texture + trigger effect/haptic pairing**
2. ✅ **Discovery reveal + ambient idle life**
3. ✅ **AR video capture → Story/share**
4. ✅ **Occlusion + lighting match**
5. ✅ **Creation live-preview + placement finesse + draw brush styles**
6. ✅ **New trigger types + in-AR reactions + Live Activity manager**
7. ⏳ Weather trigger, App Clip, Widget Extension target, multi-step sequences, sound-reactive — owner / later pass

**Shipped (client):** spatial audio, video-as-texture, trigger FX + haptics + caption, discovery reveal, ambient idle, occlusion + lighting, in-AR hype, share-in-chat, rare-find, HoloCard, AR clip→Story, gaze/ToD/long-press/multi-tap/walk-around, create preview, draw brushes, placement shadow/true-size, Live Activity manager + widget UI source.

**All device-only AR paths — untested on hardware** (status §5.7).

Every item: simulator-guard AR/Vision code, respect Reduce Motion / Low Power, keep haptics behind the system setting, and add empty/permission/error states.
