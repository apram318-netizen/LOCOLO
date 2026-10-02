//
//  AssetSearch.swift
//  Locolo
//
//  Name / description lookup for the Nearby map search, beyond the loaded
//  map area. RLS (da_select) limits it to assets the viewer may see; the
//  full 42-column row comes from get_asset_full so pins have coordinates.
//

import Foundation
import Supabase

@MainActor
enum AssetSearch {
    static func byName(_ query: String, limit: Int = 8) async -> [DigitalAsset] {
        let q = query.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: " ")
        struct Row: Decodable { let asset_id: UUID }
        guard let rows: [Row] = try? await SupabaseManager.shared.client
            .from("digital_assets")
            .select("asset_id")
            .or("name.ilike.%\(q)%,description.ilike.%\(q)%")
            .order("hype_count", ascending: false)
            .limit(limit)
            .execute()
            .value else { return [] }
        let repo = DigitalAssetRepository()
        return await withTaskGroup(of: DigitalAsset?.self) { group in
            for row in rows { group.addTask { await repo.fetchAsset(id: row.asset_id) } }
            var out: [DigitalAsset] = []
            for await asset in group { if let asset { out.append(asset) } }
            return out.sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
        }
    }
}
