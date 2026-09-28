//
//  ReactionStore.swift
//  Locolo
//
//  Phase D rich emoji reactions on assets (§5.20).
//

import Foundation
import Combine
import Supabase

@MainActor
final class ReactionStore: ObservableObject {
    static let shared = ReactionStore()
    static let palette = ["🔥", "😍", "👏", "🤯", "✨", "💜", "😂", "👀"]

    /// assetId → emoji → count
    @Published private(set) var summaries: [UUID: [String: Int]] = [:]
    @Published private(set) var mine: [UUID: String] = [:]
    @Published private(set) var available = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me { summaries = [:]; mine = [:]; available = true }
        self.me = me
    }

    func reset() {
        me = nil; summaries = [:]; mine = [:]; available = true
    }

    private struct Row: Decodable {
        let asset_id: UUID
        let emoji: String
        let reaction_count: Int
        let mine: Bool
    }

    private struct Params: Encodable { let p_assets: [String] }
    private struct Toggle: Encodable {
        let p_asset: String
        let p_emoji: String
    }

    func prime(_ assets: [DigitalAsset]) async {
        guard available, !assets.isEmpty else { return }
        do {
            let rows: [Row] = try await client
                .rpc("get_reaction_summary", params: Params(
                    p_assets: assets.map { $0.id.uuidString.lowercased() }))
                .execute()
                .value
            var next: [UUID: [String: Int]] = [:]
            var my: [UUID: String] = [:]
            for r in rows {
                next[r.asset_id, default: [:]][r.emoji] = r.reaction_count
                if r.mine { my[r.asset_id] = r.emoji }
            }
            for a in assets {
                summaries[a.id] = next[a.id] ?? [:]
                if let e = my[a.id] { mine[a.id] = e } else { mine.removeValue(forKey: a.id) }
            }
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    @discardableResult
    func toggle(assetId: UUID, emoji: String) async -> String? {
        let prev = mine[assetId]
        // Optimistic
        if prev == emoji {
            mine.removeValue(forKey: assetId)
            var s = summaries[assetId] ?? [:]
            s[emoji] = max(0, (s[emoji] ?? 1) - 1)
            if s[emoji] == 0 { s.removeValue(forKey: emoji) }
            summaries[assetId] = s
        } else {
            if let prev {
                var s = summaries[assetId] ?? [:]
                s[prev] = max(0, (s[prev] ?? 1) - 1)
                if s[prev] == 0 { s.removeValue(forKey: prev) }
                summaries[assetId] = s
            }
            mine[assetId] = emoji
            var s = summaries[assetId] ?? [:]
            s[emoji, default: 0] += 1
            summaries[assetId] = s
        }
        do {
            let result: String? = try await client
                .rpc("toggle_asset_reaction", params: Toggle(
                    p_asset: assetId.uuidString.lowercased(), p_emoji: emoji))
                .execute()
                .value
            if let result { mine[assetId] = result } else { mine.removeValue(forKey: assetId) }
            return result
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return prev
        }
    }

    func topEmojis(for assetId: UUID, limit: Int = 3) -> [(String, Int)] {
        (summaries[assetId] ?? [:])
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }
}
