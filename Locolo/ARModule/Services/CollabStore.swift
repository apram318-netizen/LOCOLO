//
//  CollabStore.swift
//  Locolo
//
//  Phase D collab credits on assets (§5.20). Separate table — no DigitalAsset RPC change.
//

import Foundation
import Combine
import Supabase

struct AssetCollab: Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    let role: String
    let royaltyBps: Int
}

@MainActor
final class CollabStore: ObservableObject {
    static let shared = CollabStore()

    @Published private(set) var collabsByAsset: [UUID: [AssetCollab]] = [:]
    @Published private(set) var available = true
    /// Prefill for create flow when tagging a collab partner.
    @Published private(set) var pendingCollabIds: [UUID] = []

    private let client = SupabaseManager.shared.client

    private init() {}

    func reset() {
        collabsByAsset = [:]
        available = true
        pendingCollabIds = []
    }

    func addPending(_ id: UUID) {
        guard !pendingCollabIds.contains(id) else { return }
        pendingCollabIds.append(id)
    }

    func removePending(_ id: UUID) {
        pendingCollabIds.removeAll { $0 == id }
    }

    func load(for assetId: UUID) async {
        guard available else { return }
        struct Row: Decodable {
            let user_id: UUID
            let role: String
            let royalty_bps: Int
        }
        do {
            let rows: [Row] = try await client
                .from("asset_collabs")
                .select("user_id, role, royalty_bps")
                .eq("asset_id", value: assetId)
                .execute()
                .value
            collabsByAsset[assetId] = rows.map {
                AssetCollab(userId: $0.user_id, role: $0.role, royaltyBps: $0.royalty_bps)
            }
            await CreatorCache.shared.load(rows.map(\.user_id))
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    func attach(assetId: UUID, userIds: [UUID], role: String = "collab") async {
        guard !userIds.isEmpty else { return }
        struct Ins: Encodable {
            let asset_id: UUID
            let user_id: UUID
            let role: String
            let royalty_bps: Int
        }
        do {
            let rows = userIds.map { Ins(asset_id: assetId, user_id: $0, role: role, royalty_bps: 0) }
            try await client.from("asset_collabs").upsert(rows).execute()
            await load(for: assetId)
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    /// Consume pending create-flow collabs after a successful insert.
    func consumePending(for assetId: UUID) async {
        let ids = pendingCollabIds
        pendingCollabIds = []
        await attach(assetId: assetId, userIds: ids)
    }
}
