//
//  SocialSession.swift
//  Locolo
//
//  Starts and tears down the app-wide social stores alongside the auth
//  session, so the next account on a shared device never sees the previous
//  user's follows, unread state, activity or notifications.
//

import Foundation
import Combine
import UIKit
import FirebaseAuth

@MainActor
enum SocialSession {
    private static var backgroundRefresh: AnyCancellable?
    private static var lastBackgroundRefresh = Date.distantPast

    static func start(me: UUID) async {
        EngagementStore.shared.configure(me: me)
        ActivityStore.shared.configure(me: me)

        async let prefs: Void = NotificationPreferences.shared.load(me: me)
        async let push: Void = PushRegistry.shared.start(me: me)
        async let follows: Void = FollowStore.shared.configure(me: me)
        async let activity: Void = ActivityStore.shared.refresh()

        // The Firestore listener needs a Firebase session; ContentView signs
        // in concurrently, so give it a moment instead of racing it.
        for _ in 0..<40 where Auth.auth().currentUser == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        InboxStore.shared.start(userId: me.uuidString)

        _ = await (prefs, push, follows, activity)
        ProximityNotifier.shared.start(me: me)
        BadgeSync.shared.start()
        startBackgroundRefresh()
    }

    static func end() {
        backgroundRefresh = nil
        ProximityNotifier.shared.stop()
        BadgeSync.shared.stop()
        NotificationPreferences.shared.reset()
        EngagementStore.shared.reset()
        FollowStore.shared.reset()
        ActivityStore.shared.reset()
        InboxStore.shared.resetForSignOut()
        CreatorCache.shared.reset()
    }

    /// While the app is kept alive in the background by location updates,
    /// piggyback on those wakes to refresh activity (at most every 5 min) so
    /// badges and local alerts stay current without a server push.
    private static func startBackgroundRefresh() {
        guard backgroundRefresh == nil else { return }
        backgroundRefresh = LocationManager.shared.$userLocation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { _ in
                guard UIApplication.shared.applicationState != .active,
                      Date().timeIntervalSince(lastBackgroundRefresh) > 300 else { return }
                lastBackgroundRefresh = Date()
                Task {
                    await ActivityStore.shared.refresh(force: true)
                    BadgeSync.shared.update()
                }
            }
    }
}
