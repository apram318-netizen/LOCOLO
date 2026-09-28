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
        case .tap:
            break // handled by the gesture recognizer via handleTap(on:)

        case .proximity:
            break // handled by updateProximity from the session frame loop

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
            // Fire the matching shake asset; ties go to whichever was registered first
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
        var current: Entity? = entity
        while let node = current {
            if let entry = placed.values.first(where: { $0.root == node }),
               entry.asset.triggerType == TriggerType.tap.rawValue {
                fire(entry.asset.id)
                return
            }
            current = node.parent
        }
    }

    // MARK: Proximity
    /// - Description: Called (throttled) from the AR frame loop with the
    /// camera position. Fires when the viewer enters an asset's radius and
    /// re-arms once they leave it plus a 2 m hysteresis margin.
    func updateProximity(cameraPosition: SIMD3<Float>) {
        for (id, entry) in placed {
            guard entry.asset.triggerType == TriggerType.proximity.rawValue,
                  let radius = entry.asset.triggerConfig?.distanceM
            else { continue }

            let assetPosition = entry.root.position(relativeTo: nil)
            let meters = Double(simd_distance(cameraPosition, assetPosition))

            if entry.armed, meters < radius {
                placed[id]?.armed = false
                fire(id)
            } else if !entry.armed, meters > radius + 2 {
                placed[id]?.armed = true
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
        placed.values.contains { $0.asset.triggerType == TriggerType.proximity.rawValue }
    }

    // MARK: Teardown
    /// - Description: Releases the mic and motion sensors and clears state.
    /// Call when the AR view disappears or resets.
    func teardown() {
        speech.stop()
        shake.stop()
        mediaPlayer.stopAll()
        placed.removeAll()
        onListeningHintChanged?(nil)
    }
}
