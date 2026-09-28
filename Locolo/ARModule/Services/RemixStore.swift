//
//  RemixStore.swift
//  Locolo
//
//  Phase D remix links (asset → parent). Separate table — does not touch
//  DigitalAsset RPC columns.
//

import Foundation
import Combine
import Supabase

@MainActor
final class RemixStore: ObservableObject {
    static let shared = RemixStore()

    @Published private(set) var parentOf: [UUID: UUID] = [:]
    @Published private(set) var childrenOf: [UUID: [UUID]] = [:]
    @Published private(set) var available = true
    /// Prefill for create flow when user taps "Remix".
    @Published var pendingParentId: UUID?

    private let client = SupabaseManager.shared.client

    private init() {}

    func reset() {
        parentOf = [:]
        childrenOf = [:]
        available = true
        pendingParentId = nil
    }

    func attach(child: UUID, parent: UUID) async {
        struct Insert: Encodable {
            let asset_id: UUID
            let parent_asset_id: UUID
        }
        do {
            try await client.from("asset_remixes")
                .insert(Insert(asset_id: child, parent_asset_id: parent))
                .execute()
            parentOf[child] = parent
            childrenOf[parent, default: []].append(child)
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    func loadParent(of assetId: UUID) async -> UUID? {
        if let cached = parentOf[assetId] { return cached }
        struct Row: Decodable { let parent_asset_id: UUID }
        do {
            let rows: [Row] = try await client.from("asset_remixes")
                .select("parent_asset_id")
                .eq("asset_id", value: assetId)
                .limit(1)
                .execute()
                .value
            if let p = rows.first?.parent_asset_id {
                parentOf[assetId] = p
                return p
            }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
        return nil
    }

    func beginRemix(of asset: DigitalAsset) {
        pendingParentId = asset.id
    }
}
