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
            let state = rows.first
            if state?.hyped == true {
                // A positive signal — fold this asset into the taste vector.
                Self.sendTasteSignal(userId: userId, assetId: assetId)
            }
            return state
        } catch {
            print("toggleHype failed:", error.localizedDescription)
            return nil
        }
    }

    /// Fire-and-forget call to the update-taste edge function (WS5.1). Folds an
    /// engaged asset's embedding into users.taste_embedding. Silently no-ops
    /// until the function is deployed — personalization just stays cold.
    static func sendTasteSignal(userId: UUID, assetId: UUID) {
        Task.detached(priority: .background) {
            // The function derives the user from the JWT; user_id is only sent
            // for backward compatibility with the pre-hardening deployment.
            guard let request = try? await EdgeFunctions.request("update-taste", body: [
                "user_id": userId.uuidString.lowercased(),
                "asset_id": assetId.uuidString.lowercased()
            ]) else { return }
            _ = try? await URLSession.shared.data(for: request)
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
