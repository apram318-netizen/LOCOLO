//
//  ExploringLiveActivity.swift
//  Locolo
//
//  Live Activity while the AR viewer is open — nearby count + nearest drop.
//  Requires ActivityKit + LocoloWidgets extension (NSSupportsLiveActivities).
//

import Foundation
import ActivityKit

struct ExploringAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var nearbyCount: Int
        var nearestName: String?
        var nearestMeters: Double?
    }

    var startedAt: Date
}

@MainActor
enum ExploringLiveActivity {
    // Qualify ActivityKit — the app also has Models.Activity (legacy events).
    private static var current: ActivityKit.Activity<ExploringAttributes>?

    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(nearbyCount: Int, nearestName: String?, nearestMeters: Double?) {
        guard isEnabled else { return }
        end()
        let attributes = ExploringAttributes(startedAt: Date())
        let state = ExploringAttributes.ContentState(
            nearbyCount: nearbyCount, nearestName: nearestName, nearestMeters: nearestMeters)
        do {
            current = try ActivityKit.Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil)
        } catch {
            LocoloLog.ar.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func update(nearbyCount: Int, nearestName: String?, nearestMeters: Double?) {
        guard let current else { return }
        let state = ExploringAttributes.ContentState(
            nearbyCount: nearbyCount, nearestName: nearestName, nearestMeters: nearestMeters)
        Task {
            await current.update(.init(state: state, staleDate: nil))
        }
    }

    static func end() {
        guard let current else { return }
        let snap = current
        self.current = nil
        Task {
            await snap.end(nil, dismissalPolicy: .immediate)
        }
    }
}
