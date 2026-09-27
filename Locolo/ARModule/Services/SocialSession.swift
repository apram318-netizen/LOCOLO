//
//  SocialSession.swift
//  Locolo
//
//  Starts and tears down the app-wide social stores alongside the auth
//  session, so the next account on a shared device never sees the previous
//  user's follows, unread state or activity.
//

import Foundation
import FirebaseAuth

@MainActor
enum SocialSession {
    static func start(me: UUID) async {
        EngagementStore.shared.configure(me: me)
        ActivityStore.shared.configure(me: me)

        async let follows: Void = FollowStore.shared.configure(me: me)
        async let activity: Void = ActivityStore.shared.refresh()

        // The Firestore listener needs a Firebase session; ContentView signs
        // in concurrently, so give it a moment instead of racing it.
        for _ in 0..<40 where Auth.auth().currentUser == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        InboxStore.shared.start(userId: me.uuidString)

        _ = await (follows, activity)
    }

    static func end() {
        EngagementStore.shared.reset()
        FollowStore.shared.reset()
        ActivityStore.shared.reset()
        InboxStore.shared.resetForSignOut()
        CreatorCache.shared.reset()
    }
}
