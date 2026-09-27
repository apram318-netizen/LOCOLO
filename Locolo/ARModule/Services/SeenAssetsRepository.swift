//
//  SeenAssetsRepository.swift
//  Locolo
//
//  Per-user record of assets explored in AR sessions, backed by the
//  asset_views table. Recording happens when an asset is actually placed
//  in the viewer's AR session; the AR profile reads it back as the
//  "Explored" list.
//

import Foundation
import Supabase

final class SeenAssetsRepository {
    static let shared = SeenAssetsRepository()
    private let client = SupabaseManager.shared.client

    private struct SeenInsert: Encodable {
        let user_id: UUID
        let asset_id: UUID
        let seen_at: Date
    }

    private struct SeenAssetRow: Decodable {
        let seenAt: Date
        let asset: DigitalAsset

        enum CodingKeys: String, CodingKey {
            case seenAt = "seen_at"
            case asset = "digital_assets"
        }
    }

    // MARK: Record an asset as seen
    /// - Description: Upserts a (user, asset) row; repeat sightings just
    /// refresh seen_at. Fire-and-forget — failures only log.
    func recordSeen(userId: UUID, assetId: UUID) async {
        do {
            try await client
                .from("asset_views")
                .upsert(
                    SeenInsert(user_id: userId, asset_id: assetId, seen_at: Date()),
                    onConflict: "user_id,asset_id"
                )
                .execute()
            // Exploring an asset in AR is a taste signal too. (WS5.1)
            AssetEngagementRepository.sendTasteSignal(userId: userId, assetId: assetId)
        } catch {
            print(" Failed to record seen asset:", error.localizedDescription)
        }
    }

    // MARK: Fetch explored assets
    /// - Description: Returns the assets this user has seen in AR, most
    /// recently seen first, via the asset_views → digital_assets embed.
    func fetchSeenAssets(userId: UUID) async throws -> [DigitalAsset] {
        try await fetchSeenHistory(userId: userId).map(\.asset)
    }

    /// Same as `fetchSeenAssets` but keeps each row's last `seen_at`, which
    /// the Explorer Passport uses for activity streaks.
    func fetchSeenHistory(userId: UUID) async throws -> [(seenAt: Date, asset: DigitalAsset)] {
        let rows: [SeenAssetRow] = try await client
            .from("asset_views")
            .select("seen_at, digital_assets(*)")
            .eq("user_id", value: userId)
            .order("seen_at", ascending: false)
            .execute()
            .value

        return rows.map { (seenAt: $0.seenAt, asset: $0.asset) }
    }
}
