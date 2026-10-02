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
        StoryStore.shared.configure(me: me)
        BoardsStore.shared.configure(me: me)
        ProgressStore.shared.configure(me: me)
        RepostStore.shared.configure(me: me)
        WalletService.shared.configure(me: me)
        ReactionStore.shared.configure(me: me)
        RemixStore.shared.reset()
        PollStore.shared.configure(me: me)
        PresenceStore.shared.configure(me: me)
        EventsStore.shared.configure(me: me)
        CollabStore.shared.reset()
        MemoryStore.shared.configure(me: me)
        PostStore.shared.configure(me: me)
        // Settles App Store mint purchases interrupted before verification (needs a session).
        MintPurchaseService.shared.start()

        async let prefs: Void = NotificationPreferences.shared.load(me: me)
        async let push: Void = PushRegistry.shared.start(me: me)
        async let follows: Void = FollowStore.shared.configure(me: me)
        async let activity: Void = ActivityStore.shared.refresh()
        async let stories: Void = StoryStore.shared.refresh()
        async let boards: Void = BoardsStore.shared.refresh()
        async let tags: Void = TagStore.shared.refreshTrending()
        async let progress: Void = ProgressStore.shared.refresh()
        async let wallets: Void = WalletService.shared.refresh()
        async let safetyExtras: Void = SafetyExtrasStore.shared.configure(me: me)
        async let events: Void = EventsStore.shared.refresh()
        async let features: Void = AppFeatures.shared.refresh()

        // The Firestore listener needs a Firebase session; ContentView signs
        // in concurrently, so give it a moment instead of racing it.
        for _ in 0..<40 where Auth.auth().currentUser == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        InboxStore.shared.start(userId: me.uuidString)

        _ = await (prefs, push, follows, activity, stories, boards, tags, progress, wallets, safetyExtras, events, features)
        ProximityNotifier.shared.start(me: me)
        BadgeSync.shared.start()
        startBackgroundRefresh()
        BackgroundExploreService.shared.restoreIfNeeded()
        Task { await PresenceStore.shared.heartbeat() }
    }

    static func end() {
        backgroundRefresh = nil
        ProximityNotifier.shared.stop()
        BadgeSync.shared.stop()
        NotificationPreferences.shared.reset()
        EngagementStore.shared.reset()
        FollowStore.shared.reset()
        ActivityStore.shared.reset()
        StoryStore.shared.reset()
        BoardsStore.shared.reset()
        TagStore.shared.reset()
        ProgressStore.shared.reset()
        RepostStore.shared.reset()
        WalletService.shared.reset()
        AppFeatures.shared.reset()
        ReactionStore.shared.reset()
        RemixStore.shared.reset()
        PollStore.shared.reset()
        PresenceStore.shared.reset()
        EventsStore.shared.reset()
        SafetyExtrasStore.shared.reset()
        CollabStore.shared.reset()
        MemoryStore.shared.reset()
        PostStore.shared.reset()
        BackgroundExploreService.shared.stop()
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
