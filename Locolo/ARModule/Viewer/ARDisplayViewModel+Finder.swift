//
//  ARDisplayViewModel+Finder.swift
//  Locolo
//
//  Hot/cold finder for the AR viewer: points at the nearest asset you
//  haven't found yet, says whether you're getting warmer or colder, and
//  pulses haptics faster as you close in. Walking within `foundRadius`
//  marks the asset found (DiscoveryStore → Explorer Passport).
//

import Foundation
import CoreLocation

enum FinderTrend {
    case warmer, colder, steady
}

extension ARDisplayViewModel {
    struct FinderTarget: Equatable {
        let asset: DigitalAsset
        let distance: Double
        /// Radians clockwise from the direction the device is facing; nil
        /// until the compass reports a heading.
        let relativeAngle: Double?

        static func == (lhs: FinderTarget, rhs: FinderTarget) -> Bool {
            lhs.asset.id == rhs.asset.id && lhs.distance == rhs.distance
                && lhs.relativeAngle == rhs.relativeAngle
        }
    }

    /// Close enough to count as found — generous, since GPS drifts 5–10 m.
    static let foundRadius: Double = 12
    /// Beyond this the finder stays quiet (the radar covers the big picture).
    static let finderRange: Double = 1_000
    /// Haptic pulses only kick in inside this radius.
    static let hapticRange: Double = 60

    var finderTarget: FinderTarget? {
        guard let origin = userLocation else { return nil }
        let discoveries = DiscoveryStore.shared
        let candidates = nearbyAssets.compactMap { asset -> (DigitalAsset, Double)? in
            guard !discoveries.hasFound(asset.id),
                  let lat = asset.latitude, let lon = asset.longitude else { return nil }
            let d = origin.distance(from: CLLocation(latitude: lat, longitude: lon))
            return d <= Self.finderRange ? (asset, d) : nil
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }),
              let lat = nearest.0.latitude, let lon = nearest.0.longitude else { return nil }
        let (asset, distance) = nearest

        var relative: Double?
        if let heading = headingDegrees {
            let absolute = bearing(from: origin.coordinate,
                                   to: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            relative = absolute - heading * .pi / 180
        }
        return FinderTarget(asset: asset, distance: distance, relativeAngle: relative)
    }

    /// Called on every location fix: updates the warmer/colder trend and
    /// marks assets found when the user reaches them.
    func updateFinder() {
        guard isLocalized, let target = finderTarget else {
            finderTrend = .steady
            finderLastDistance = nil
            finderLastTargetId = nil
            return
        }

        if target.distance <= Self.foundRadius {
            if DiscoveryStore.shared.markFound(target.asset.id) {
                justFound = target.asset
                ARHaptics.success()
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if self?.justFound?.id == target.asset.id { self?.justFound = nil }
                }
            }
            finderLastDistance = nil
            finderLastTargetId = nil
            finderTrend = .steady
            return
        }

        // Only compare against the same target, and ignore sub-2 m jitter.
        if finderLastTargetId == target.asset.id, let last = finderLastDistance {
            let delta = target.distance - last
            if delta < -2 {
                finderTrend = .warmer
                finderLastDistance = target.distance
            } else if delta > 2 {
                finderTrend = .colder
                finderLastDistance = target.distance
            }
        } else {
            finderLastTargetId = target.asset.id
            finderLastDistance = target.distance
            finderTrend = .steady
        }
    }

    /// Runs for the lifetime of the viewer (`.task` cancels it): a haptic
    /// "heartbeat" that speeds up and strengthens as the target gets closer.
    func runFinderPulses() async {
        while !Task.isCancelled {
            var wait = 1.5
            if isLocalized, let target = finderTarget, target.distance < Self.hapticRange {
                let closeness = 1 - target.distance / Self.hapticRange
                ARHaptics.pulse(intensity: CGFloat(0.3 + 0.7 * closeness))
                wait = max(0.3, min(2.0, target.distance / 25))
            }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    static func formatDistance(_ meters: Double) -> String {
        meters < 1_000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1_000)
    }
}
