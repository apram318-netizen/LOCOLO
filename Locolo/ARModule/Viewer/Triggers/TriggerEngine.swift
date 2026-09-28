//
//  TriggerEngine.swift
//  Locolo
//
//  Owns the per-asset trigger detectors during an AR session. Assets are
//  registered as they're placed; when an asset's trigger fires, the engine
//  plays the animation and/or sidecar media the poster chose for it.
//

import Foundation
import RealityKit
import simd

@MainActor
final class TriggerEngine {

    struct Placed {
        let asset: DigitalAsset
        let root: Entity
        var armed = true
    }

    private var placed: [UUID: Placed] = [:]
    /// Per-asset gaze dwell accumulator (seconds).
    private var gazeAccum: [UUID: Double] = [:]
    /// Multi-tap: recent tap timestamps per asset.
    private var tapStamps: [UUID: [Date]] = [:]
    /// Walk-around: last camera bearing (radians) + accumulated orbit (degrees).
    private var orbitLastBearing: [UUID: Float] = [:]
    private var orbitAccumDeg: [UUID: Double] = [:]
    private let speech = SpeechTriggerService()
    private let shake = ShakeDetector()
    private let mediaPlayer = ARMediaPlaybackController()

    /// Set when speech listening starts, for the status banner.
    var onListeningHintChanged: ((String?) -> Void)?
    var onPlaybackMessage: ((String) -> Void)?
    /// Fired (main thread) when any asset's trigger activates, so the view can
    /// show an on-screen flourish/caption.
    var onTriggerFired: ((DigitalAsset) -> Void)?

    // MARK: Register a placed asset
    /// - Description: Called after a model is anchored. Sets up whichever
    /// detector its trigger needs. Assets without animation or media are ignored.
    func register(asset: DigitalAsset, rootEntity: Entity) {
        let hasAnimation = asset.animationIndex != nil || asset.animationName != nil
        let hasMedia = asset.mediaUrl != nil

        guard hasAnimation || hasMedia,
              let triggerRaw = asset.triggerType,
              let trigger = TriggerType(rawValue: triggerRaw)
        else { return }

        placed[asset.id] = Placed(asset: asset, root: rootEntity)
        mediaPlayer.onPlaybackMessage = onPlaybackMessage

        switch trigger {
        case .tap, .longPress, .multiTap:
            break // handled by gesture recognizers

        case .proximity, .gaze, .timeOfDay, .walkAround:
            break // handled from the session frame loop

        case .speech:
            if let phrase = asset.triggerConfig?.phrase {
                let id = asset.id
                speech.listen(for: phrase) { [weak self] in
                    self?.fire(id)
                }
                onListeningHintChanged?(speech.listeningHint)
            }

        case .shake:
            startShakeIfNeeded()
        }
    }

    private func startShakeIfNeeded() {
        shake.start { [weak self] pattern in
            guard let self else { return }
            for entry in self.placed.values {
                guard entry.asset.triggerType == TriggerType.shake.rawValue,
                      entry.asset.triggerConfig?.shakePattern == pattern
                else { continue }
                self.fire(entry.asset.id)
                break
            }
        }
    }

    // MARK: Tap handling
    /// - Description: Walks up from the tapped (leaf) entity to a registered
    /// root, since hit tests return child ModelEntities.
    func handleTap(on entity: Entity) {
        guard let entry = placedEntry(containing: entity) else { return }
        let type = entry.asset.triggerType
        if type == TriggerType.tap.rawValue {
            fire(entry.asset.id)
            return
        }
        if type == TriggerType.multiTap.rawValue {
            let need = max(2, entry.asset.triggerConfig?.tapCount ?? 3)
            var stamps = (tapStamps[entry.asset.id] ?? []).filter {
                Date().timeIntervalSince($0) < 1.4
            }
            stamps.append(Date())
            tapStamps[entry.asset.id] = stamps
            if stamps.count >= need {
                tapStamps[entry.asset.id] = []
                fire(entry.asset.id)
            }
        }
    }

    /// Long-press "pet" trigger.
    func handleLongPress(on entity: Entity) {
        guard let entry = placedEntry(containing: entity),
              entry.asset.triggerType == TriggerType.longPress.rawValue
        else { return }
        fire(entry.asset.id)
    }

    private func placedEntry(containing entity: Entity) -> Placed? {
        var current: Entity? = entity
        while let node = current {
            if let entry = placed.values.first(where: { $0.root == node }) {
                return entry
            }
            current = node.parent
        }
        return nil
    }

    // MARK: Frame-driven triggers (proximity / gaze / time-of-day / orbit)
    /// Called (throttled) from the AR frame loop.
    func updateProximity(cameraPosition: SIMD3<Float>,
                         cameraForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)) {
        let hour = Calendar.current.component(.hour, from: Date())
        for (id, entry) in placed {
            let type = entry.asset.triggerType
            let assetPosition = entry.root.position(relativeTo: nil)
            let meters = Double(simd_distance(cameraPosition, assetPosition))

            if type == TriggerType.proximity.rawValue,
               let radius = entry.asset.triggerConfig?.distanceM {
                if entry.armed, meters < radius {
                    placed[id]?.armed = false
                    fire(id)
                } else if !entry.armed, meters > radius + 2 {
                    placed[id]?.armed = true
                }
                continue
            }

            if type == TriggerType.gaze.rawValue {
                let need = entry.asset.triggerConfig?.gazeSeconds ?? 1.5
                let toAsset = simd_normalize(assetPosition - cameraPosition)
                let looking = simd_dot(simd_normalize(cameraForward), toAsset) > 0.92
                if looking, meters < 40 {
                    gazeAccum[id, default: 0] += 1.0 / 6.0 // ~frame throttle of 10 @ 60fps → ~6 Hz
                    if entry.armed, (gazeAccum[id] ?? 0) >= need {
                        placed[id]?.armed = false
                        gazeAccum[id] = 0
                        fire(id)
                    }
                } else {
                    gazeAccum[id] = 0
                    if !entry.armed, meters > 8 { placed[id]?.armed = true }
                }
                continue
            }

            if type == TriggerType.timeOfDay.rawValue {
                let start = entry.asset.triggerConfig?.startHour ?? 0
                let end = entry.asset.triggerConfig?.endHour ?? 24
                let inWindow: Bool = {
                    if start == end { return true }
                    if start < end { return hour >= start && hour < end }
                    return hour >= start || hour < end // wraps midnight
                }()
                if entry.armed, inWindow, meters < 25 {
                    placed[id]?.armed = false
                    fire(id)
                } else if !entry.armed, !inWindow {
                    placed[id]?.armed = true
                }
                continue
            }

            if type == TriggerType.walkAround.rawValue {
                let need = entry.asset.triggerConfig?.orbitDegrees ?? 270
                guard meters < 12, meters > 0.8 else {
                    orbitLastBearing[id] = nil
                    continue
                }
                let dx = cameraPosition.x - assetPosition.x
                let dz = cameraPosition.z - assetPosition.z
                let bearing = atan2(dz, dx)
                if let last = orbitLastBearing[id] {
                    var delta = bearing - last
                    // Wrap to [-π, π]
                    while delta > .pi { delta -= 2 * .pi }
                    while delta < -.pi { delta += 2 * .pi }
                    orbitAccumDeg[id, default: 0] += abs(Double(delta) * 180 / .pi)
                }
                orbitLastBearing[id] = bearing
                if entry.armed, (orbitAccumDeg[id] ?? 0) >= need {
                    placed[id]?.armed = false
                    orbitAccumDeg[id] = 0
                    fire(id)
                } else if !entry.armed, meters > 16 {
                    placed[id]?.armed = true
                    orbitAccumDeg[id] = 0
                }
            }
        }
    }

    // MARK: Fire an asset's animation/media
    /// - Description: Resolves the stored animation (index first, then name,
    /// then first available) and plays it once. Also plays any attached
    /// sidecar media.
    func fire(_ id: UUID) {
        guard let entry = placed[id] else { return }

        playAnimationIfAvailable(for: entry)
        mediaPlayer.playMedia(for: entry.asset, on: entry.root)

        // Sensory pairing: a quick scale-pop on the entity + a haptic, so every
        // trigger feels physical even for assets without an embedded animation.
        popEffect(on: entry.root)
        ARHaptics.triggerFired()
        onTriggerFired?(entry.asset)
    }

    /// A brief squash-and-stretch pop, then settle back to the resting scale.
    private func popEffect(on entity: Entity) {
        let base = entity.scale
        var popped = entity.transform
        popped.scale = base * 1.12
        entity.move(to: popped, relativeTo: entity.parent, duration: 0.12, timingFunction: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { [weak entity] in
            guard let entity else { return }
            var settle = entity.transform
            settle.scale = base
            entity.move(to: settle, relativeTo: entity.parent, duration: 0.18, timingFunction: .easeInOut)
        }
    }

    private func playAnimationIfAvailable(for entry: Placed) {
        let host = entityWithAnimations(in: entry.root) ?? entry.root
        let animations = host.availableAnimations
        guard !animations.isEmpty else { return }

        let resource = entry.asset.animationIndex
            .flatMap { animations.indices.contains($0) ? animations[$0] : nil }
            ?? animations.first { $0.name == entry.asset.animationName }
            ?? animations[0]

        host.playAnimation(resource.repeat(count: 1), transitionDuration: 0.2)
    }

    private func entityWithAnimations(in root: Entity) -> Entity? {
        if !root.availableAnimations.isEmpty { return root }
        for child in root.children {
            if let found = entityWithAnimations(in: child) { return found }
        }
        return nil
    }

    // MARK: Whether any registered asset needs the frame loop
    var hasProximityAssets: Bool {
        placed.values.contains {
            let t = $0.asset.triggerType
            return t == TriggerType.proximity.rawValue
                || t == TriggerType.gaze.rawValue
                || t == TriggerType.timeOfDay.rawValue
                || t == TriggerType.walkAround.rawValue
        }
    }

    // MARK: Teardown
    /// - Description: Releases the mic and motion sensors and clears state.
    /// Call when the AR view disappears or resets.
    func teardown() {
        speech.stop()
        shake.stop()
        mediaPlayer.stopAll()
        placed.removeAll()
        gazeAccum.removeAll()
        tapStamps.removeAll()
        orbitLastBearing.removeAll()
        orbitAccumDeg.removeAll()
        onListeningHintChanged?(nil)
    }
}
