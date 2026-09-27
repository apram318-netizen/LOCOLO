//
//  AssetEngagementRepository.swift
//  Locolo
//
//  Hype engagement for AR assets (WS5.4), backed by the asset_hype table and
//  the atomic toggle_asset_hype RPC (keeps hype_count in sync server-side).
//

import Foundation
import Supabase

final class AssetEngagementRepository {
    static let shared = AssetEngagementRepository()
    private let client = SupabaseManager.shared.client

    private init() {}

    struct HypeState: Decodable {
        let hyped: Bool
        let hype_count: Int
    }

    private struct ToggleParams: Encodable {
        let p_user: String
        let p_asset: String
    }

    private struct HypeKeyRow: Decodable {
        let asset_id: UUID
    }

    /// Toggle the user's hype on an asset. Returns the new state, or nil on failure.
    func toggleHype(userId: UUID, assetId: UUID) async -> HypeState? {
        do {
            let rows: [HypeState] = try await client
                .rpc("toggle_asset_hype", params: ToggleParams(
                    p_user: userId.uuidString, p_asset: assetId.uuidString))
                .execute()
                .value
            return rows.first
        } catch {
            print("toggleHype failed:", error.localizedDescription)
            return nil
        }
    }

    /// Whether the user has hyped this asset.
    func isHyped(userId: UUID, assetId: UUID) async -> Bool {
        do {
            let rows: [HypeKeyRow] = try await client
                .from("asset_hype")
                .select("asset_id")
                .eq("user_id", value: userId)
                .eq("asset_id", value: assetId)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            return false
        }
    }
}
