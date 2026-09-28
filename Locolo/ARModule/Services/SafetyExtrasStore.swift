//
//  SafetyExtrasStore.swift
//  Locolo
//
//  Close friends + mute list (§5.20). Complements SafetyService blocks.
//

import Foundation
import Combine
import Supabase

@MainActor
final class SafetyExtrasStore: ObservableObject {
    static let shared = SafetyExtrasStore()

    @Published private(set) var closeFriends: Set<UUID> = []
    @Published private(set) var muted: Set<UUID> = []
    @Published private(set) var available = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) async {
        self.me = me
        await refresh()
    }

    func reset() {
        me = nil
        closeFriends = []
        muted = []
        available = true
    }

    func isMuted(_ id: UUID) -> Bool { muted.contains(id) }
    func isCloseFriend(_ id: UUID) -> Bool { closeFriends.contains(id) }

    func refresh() async {
        guard let me else { return }
        do {
            struct CF: Decodable { let friend_id: UUID }
            struct MU: Decodable { let muted_id: UUID }
            let friends: [CF] = try await client.from("close_friends")
                .select("friend_id").eq("owner_id", value: me).execute().value
            let mutes: [MU] = try await client.from("user_mutes")
                .select("muted_id").eq("muter_id", value: me).execute().value
            closeFriends = Set(friends.map(\.friend_id))
            muted = Set(mutes.map(\.muted_id))
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    func toggleCloseFriend(_ id: UUID) async {
        guard let me else { return }
        if closeFriends.contains(id) {
            closeFriends.remove(id)
            _ = try? await client.from("close_friends").delete()
                .eq("owner_id", value: me).eq("friend_id", value: id).execute()
        } else {
            closeFriends.insert(id)
            struct Ins: Encodable { let owner_id: UUID; let friend_id: UUID }
            _ = try? await client.from("close_friends")
                .insert(Ins(owner_id: me, friend_id: id)).execute()
        }
    }

    func toggleMute(_ id: UUID) async {
        guard let me else { return }
        if muted.contains(id) {
            muted.remove(id)
            _ = try? await client.from("user_mutes").delete()
                .eq("muter_id", value: me).eq("muted_id", value: id).execute()
        } else {
            muted.insert(id)
            struct Ins: Encodable { let muter_id: UUID; let muted_id: UUID }
            _ = try? await client.from("user_mutes")
                .insert(Ins(muter_id: me, muted_id: id)).execute()
        }
    }
}
