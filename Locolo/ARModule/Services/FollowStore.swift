//
//  FollowStore.swift
//  Locolo
//
//  The signed-in user's following set, shared by every Follow button (feed
//  suggestions, detail sheet, profiles, search, activity) so they all flip
//  together and the "Following" feed filter has something to filter by.
//

import Foundation
import Combine
import Supabase

@MainActor
final class FollowStore: ObservableObject {
    static let shared = FollowStore()

    @Published private(set) var following: Set<UUID> = []
    @Published private(set) var isLoaded = false
    @Published private(set) var pending: Set<UUID> = []

    private let client = SupabaseManager.shared.client
    private let repo = FollowRepository()
    private(set) var me: UUID?

    private init() {}

    private struct FolloweeRow: Decodable { let followee_id: UUID }

    func configure(me: UUID) async {
        if self.me != me { reset() }
        self.me = me
        await reload()
    }

    func reload() async {
        guard let me else { return }
        do {
            let rows: [FolloweeRow] = try await client
                .from("follows")
                .select("followee_id")
                .eq("follower_id", value: me)
                .eq("status", value: "accepted")
                .execute()
                .value
            following = Set(rows.map(\.followee_id))
            isLoaded = true
        } catch {
            print("FollowStore reload failed:", error.localizedDescription)
        }
    }

    func reset() {
        me = nil
        following = []
        pending = []
        isLoaded = false
    }

    func isFollowing(_ id: UUID) -> Bool { following.contains(id) }

    /// Records a state learned elsewhere (e.g. a profile's own isFollowing check).
    func mark(_ id: UUID, following isOn: Bool) {
        if isOn { following.insert(id) } else { following.remove(id) }
    }

    /// Optimistic follow/unfollow. Returns the resulting state.
    @discardableResult
    func toggle(_ target: UUID) async -> Bool {
        guard let me, target != me, !pending.contains(target) else { return isFollowing(target) }
        pending.insert(target)
        defer { pending.remove(target) }

        let wasFollowing = following.contains(target)
        mark(target, following: !wasFollowing)
        do {
            if wasFollowing {
                try await repo.unfollow(target, from: me)
            } else {
                try await repo.follow(target, from: me)
            }
            return !wasFollowing
        } catch {
            mark(target, following: wasFollowing)
            print("Follow toggle failed:", error.localizedDescription)
            return wasFollowing
        }
    }
}
