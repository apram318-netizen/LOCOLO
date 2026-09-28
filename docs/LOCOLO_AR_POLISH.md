# LOCOLO — AR Experience Polish & Feature Backlog

> Focused enhancement backlog for the **AR module specifically** — making what already exists look better, feel more premium ("more phone"), and function richer. Distinct from the big new pillars in `LOCOLO_V2_*` (marketplace/social/security). Non-AR screens stay in the app for now (per owner: separate them out closer to release).
> Reuses `TriggerEngine`, `ARMediaPlaybackController`, `SpeechTriggerService`, `ShakeDetector`, `ARDisplayViewModel`, `ARComponents.swift`, `ARDesign.swift`.

---

## What exists today (baseline)
- Viewer: geo + GPS-fallback placement, radar, hot/cold finder, snapshots, coaching overlay, re-anchoring, mode switch.
- **Interactions/triggers:** one trigger per asset — **tap / proximity / speech / shake** — that fires the asset's **embedded USDZ animation** and plays **sidecar audio/video** (`ARMediaPlaybackController`; video currently plays its *audio track* only).
- Creation: place with north-aligned quaternion, pick animation + trigger + media, hand-draw.
- Share-in-chat ✅ (done — asset sends as an E2E rich card).

## Priorities at a glance
1. **Interaction & sensory richness** (the "animations + music" ask, expanded) — the highest-impact AR wow-factor.
2. **Viewer visual polish** — make discovery feel magical and premium.
3. **Creation flow polish** — make placing feel effortless and expressive.
4. **Instagram-parity AR social hooks** — beyond share-in-chat.
5. **"More phone" native touches** — the small premium details.

---

## 1. Interaction & sensory richness (build first)

The trigger system is the AR magic — deepen it.

- **Spatial/3D audio.** Route `ARMediaPlaybackController` audio through `AVAudioEnvironmentNode` / RealityKit spatial audio so sound comes *from the asset's position* and attenuates with distance. This alone makes AR feel real. (Today it's flat stereo.)
- **Video-as-texture.** Render MP4/MOV onto a plane or the model's surface (`VideoMaterial` in RealityKit) instead of audio-only — a floating animated screen in the world.
- **Trigger → effect pairing.** When a trigger fires, don't just play the clip: add a **particle burst / glow / scale-pop** on the entity, a **haptic pulse** synced to the beat, and an on-screen caption ("✨ You woke it up"). Reuse `ReactionBurst`/`ConfettiView` from the V2 UI components.
- **Multi-step animation sequences.** Let a creator chain animations ("idle → on-tap: jump → loop dance") rather than one clip. Extend `trigger_config` with a small sequence array.
- **More trigger types:**
  - **Time-of-day / golden-hour** (only animates at sunset), **weather** (reacts to real conditions via a weather API), **look-at / gaze** (animates when centered in view), **long-press to "pet"**, **multi-tap combo**, **walk-around** (plays as you orbit it).
- **Reactions in AR.** Hype/emoji-react on an asset from *inside* the viewer (floating tap target), with a burst that other nearby explorers could see (presence, V2).
- **Ambient life.** Idle micro-animations (gentle bob/rotate/breathing) so placed assets never look frozen while waiting for a trigger.
- **Sound-reactive assets.** `interaction_type = 'audio-reactive'` already exists in the enum — make assets pulse/scale to the mic amplitude or their own audio track.

## 2. Viewer visual polish (make discovery magical)

- **Discovery reveal.** First time an asset resolves into view: a shimmer/materialize-in animation + soft chime + haptic, instead of a hard pop-in. A "rare find" gets a bigger flourish (holo sparkle, stronger haptic).
- **Distance & depth cues.** Subtle ground shadow/contact circle under each asset; a faint glow halo that scales with proximity; a floating name/creator label that fades in when you look at it (billboarded toward the camera).
- **Radar upgrade.** Directional pulse toward the nearest asset; tap a blip to get an on-screen arrow + distance; color blips by rarity/for-sale.
- **Onboarding-in-AR.** A ghosted hand/phone hint on first session ("move your phone to find art"); calibration nudge when heading accuracy is poor (ties into the existing compass gate).
- **Occlusion & realism** (device-dependent): enable people/scene occlusion (`ARWorldTrackingConfiguration.frameSemantics = .personSegmentationWithDepth`, LiDAR scene mesh where available) so assets sit *behind* real objects — a huge realism jump on capable devices, gracefully degraded elsewhere.
- **Lighting match.** Use ARKit's estimated environment lighting/probes so assets are lit like their surroundings (less "pasted on").
- **Snapshot → Story/Reel.** Record a short AR **video clip** (not just a photo), add the branded frame + music, share to a Story (V2 social) or externally. Video capture of `ARView` via `RealityKit`'s frame capture or `ReplayKit`.

## 3. Creation flow polish

- **Live preview with real triggers.** Preview the chosen animation + trigger + audio *before* posting, in a mini AR canvas.
- **Placement finesse.** Snap-to-surface, scale/rotate with two-finger gestures + a fine-tune inspector, a "true size" toggle, and a shadow so you can judge grounding. Undo/redo.
- **Templates & effects.** Starter pack of animated assets and effect presets for people without their own USDZ; a "make it glow/holographic/neon" material picker.
- **Multi-asset scenes.** Place a small arrangement (e.g. 3 pieces) as one drop.
- **Draw upgrades** (`ARModule/Draw`): brush styles (neon/ribbon/tube), animated strokes (draw-on reveal), symmetry mode, and calibrate the Vision→screen mapping on device (flagged in status doc).
- **Caption/tag step.** Hashtags, @collab, and a "list for sale?" step (feeds the marketplace).

## 4. Instagram-parity AR social hooks (beyond share-in-chat ✅)

- **Save to Collection/Board** from the viewer and detail sheet (V2 social).
- **"Who's here" / found-by** on an asset — social proof of discoverers.
- **Remix in place** — anchor your own asset next to someone's (V2 social; AR-native duet).
- **Story from a discovery** — one tap from snapshot/clip to a 24h Story.
- **Deep-link everything** — every asset/creator already deep-links; make sure viewer, radar finds, and shares all route through it (`DeepLinkRouter`).
- **Tag people/places in an asset**; show it on their profile ("featured in").

## 5. "More phone" — native premium touches

- **Haptics everywhere meaningful** (extend `ARHaptics`): placement confirm, discovery, trigger fire, found-it, hype — each a distinct pattern.
- **Live Activity / Dynamic Island** while exploring ("2 AR pieces within 100 m"), and for an active auction/offer (V2).
- **Widgets** — "AR art near you" home-screen widget; App Clip for a place ("point your camera here").
- **Focus/Standby** friendly; **ProMotion**-smooth animations; **spatial-audio** with AirPods.
- **Handoff & share sheet** polish; **Shortcuts/Siri** ("Hey Siri, what's nearby on Locolo").
- **Performance felt as polish:** keep the 40-entity cap but add LOD (simpler mesh at distance), preload nearby models via `MediaCache`, and a graceful low-power mode.

---

## Suggested build order
1. ✅ **Spatial audio + video-as-texture + trigger effect/haptic pairing** — DONE (`ebd23ee`). Spatial `AudioFileResource`, `VideoMaterial` screen, scale-pop + haptic + "✨ came to life" caption on every trigger.
2. ✅ **Discovery reveal + ambient idle life** — DONE (`ebd23ee`). Materialize-in scale, gentle idle bob, discovery haptic.
3. **AR video capture → Story/share** — the shareable moment (pairs with V2 stories). (snapshots already exist; video is the new part.)
4. ✅ **Occlusion + lighting match** (device-gated) — DONE (`ebd23ee`). Person-segmentation + LiDAR mesh occlusion + image-based lighting.
5. **Creation live-preview + placement finesse + draw upgrades.**
6. **New trigger types, ~~in-AR reactions~~, Live Activity/widgets** — in-AR hype ✅ DONE (floating bolt button hypes the nearest asset via EngagementStore, with a burst). Remaining: new trigger types, Live Activity/widgets.

**Shipped so far:** spatial audio, video-as-texture, trigger FX + haptics + caption, discovery reveal, ambient idle, occlusion + lighting, in-AR hype reactions, share-asset-in-chat. **All device-only — untested on hardware.**
**Next up:** AR video capture → Story; creation live-preview + placement finesse + draw brush styles; new trigger types (gaze / time-of-day / weather); Live Activity while exploring; widgets/App Clip.

Every item: simulator-guard AR/Vision code, respect Reduce Motion / Low Power, keep haptics behind the system setting, and add empty/permission/error states. On-device testing is required for all of §1–2 (the whole AR surface is unverified on hardware — see status doc §5.7).
