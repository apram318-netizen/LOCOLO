//
//  ARDisplayViewModel+Reactions.swift
//  Locolo
//
//  In-AR reactions: hype the asset you're standing at without leaving the
//  camera — the Instagram "double-tap to like", AR-native. Routes through the
//  shared EngagementStore so counts stay consistent everywhere.
//

import Foundation
import CoreLocation

extension ARDisplayViewModel {
    /// The closest placed asset to the viewer (within a generous reach), so a
    /// reaction targets whatever you're looking at.
    var nearestReactableAsset: DigitalAsset? {
        let inScene = nearbyAssets
        guard !inScene.isEmpty else { return nil }
        guard let origin = userLocation else { return inScene.first }
        return inScene.min { a, b in
            distance(of: a, from: origin) < distance(of: b, from: origin)
        }
    }

    private func distance(of asset: DigitalAsset, from origin: CLLocation) -> Double {
        guard let lat = asset.latitude, let lon = asset.longitude else { return .greatestFiniteMagnitude }
        return origin.distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    /// Hype the nearest asset. Returns the asset if it became hyped (for a
    /// one-shot burst), nil if un-hyped or nothing nearby.
    @discardableResult
    func hypeNearest() async -> DigitalAsset? {
        guard let asset = nearestReactableAsset else { return nil }
        let nowHyped = await EngagementStore.shared.toggleHype(asset)
        if nowHyped {
            ARHaptics.success()
            triggerFlash = "⚡️ Hyped \(asset.name ?? "this")"
            let name = asset.name ?? "this"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                if self?.triggerFlash == "⚡️ Hyped \(name)" { self?.triggerFlash = nil }
            }
            return asset
        }
        ARHaptics.tick()
        return nil
    }

    /// Whether the nearest asset is already hyped (drives the button's fill).
    var nearestIsHyped: Bool {
        guard let asset = nearestReactableAsset else { return false }
        return EngagementStore.shared.isHyped(asset.id)
    }
}
