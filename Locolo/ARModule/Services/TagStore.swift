//
//  TagStore.swift
//  Locolo
//
//  Phase D hashtags. Trending tags + set/get per asset. Degrades when the
//  hashtags migration hasn't been applied.
//

import Foundation
import Combine
import Supabase

struct TagItem: Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let label: String
    var useCount: Int
}

@MainActor
final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private(set) var trending: [TagItem] = []
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false

    private let client = SupabaseManager.shared.client

    private init() {}

    func reset() {
        trending = []
        available = true
        hasLoaded = false
    }

    private struct TrendRow: Decodable {
        let slug: String
        let label: String
        let use_count: Int
    }

    private struct TagRow: Decodable {
        let slug: String
        let label: String
    }

    private struct AssetIdRow: Decodable {
        let asset_id: UUID
    }

    private struct TrendParams: Encodable { let p_limit: Int }
    private struct AssetParams: Encodable { let p_asset: String }
    private struct ByTagParams: Encodable {
        let p_slug: String
        let p_limit: Int
    }
    private struct SetParams: Encodable {
        let p_asset: String
        let p_tags: [String]
    }

    func refreshTrending() async {
        do {
            let rows: [TrendRow] = try await client
                .rpc("get_trending_tags", params: TrendParams(p_limit: 20))
                .execute()
                .value
            available = true
            trending = rows.map {
                TagItem(slug: $0.slug, label: $0.label, useCount: $0.use_count)
            }
        } catch {
            if EngagementStore.isMissingSchema(error) {
                available = false
                trending = []
            }
        }
        hasLoaded = true
    }

    func tags(for assetId: UUID) async -> [TagItem] {
        do {
            let rows: [TagRow] = try await client
                .rpc("get_asset_tags", params: AssetParams(p_asset: assetId.uuidString.lowercased()))
                .execute()
                .value
            available = true
            return rows.map { TagItem(slug: $0.slug, label: $0.label, useCount: 0) }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return []
        }
    }

    func setTags(_ raw: [String], on assetId: UUID) async {
        let cleaned = Self.normalizeList(raw)
        do {
            try await client
                .rpc("set_asset_tags", params: SetParams(
                    p_asset: assetId.uuidString.lowercased(),
                    p_tags: cleaned))
                .execute()
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            print("set_asset_tags failed:", error.localizedDescription)
        }
    }

    func assets(forTag slug: String) async -> [DigitalAsset] {
        do {
            let ids: [AssetIdRow] = try await client
                .rpc("get_assets_by_tag", params: ByTagParams(
                    p_slug: slug, p_limit: 40))
                .execute()
                .value
            guard !ids.isEmpty else { return [] }
            let assets: [DigitalAsset] = try await client
                .from("digital_assets_flat")
                .select()
                .in("asset_id", values: ids.map { $0.asset_id.uuidString })
                .execute()
                .value
            let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element.asset_id, $0.offset) })
            return SafetyService.shared.visible(assets)
                .sorted { (order[$0.id] ?? 999) < (order[$1.id] ?? 999) }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return []
        }
    }

    /// Split a free-text tags field into normalized slugs (max 8).
    static func normalizeList(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for piece in raw {
            for part in piece.split(whereSeparator: { ",# \t\n".contains($0) }) {
                let s = String(part)
                    .lowercased()
                    .replacingOccurrences(of: #"^#+"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[^a-z0-9_]+"#, with: "_", options: .regularExpression)
                guard s.count >= 2, s.count <= 32, !seen.contains(s) else { continue }
                seen.insert(s)
                out.append(s)
                if out.count >= 8 { return out }
            }
        }
        return out
    }

    static func normalizeList(from text: String) -> [String] {
        normalizeList([text])
    }
}
