//
//  RepostStore.swift
//  Locolo
//
//  Phase D re-drops. Toggle via toggle_repost; primes counts for the feed.
//  Hides when §5.15 migration isn't applied.
//

import Foundation
import Combine
import Supabase

@MainActor
final class RepostStore: ObservableObject {
    static let shared = RepostStore()

    @Published private(set) var reposted: Set<UUID> = []
    @Published private(set) var counts: [UUID: Int] = [:]
    @Published private(set) var available = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me {
            reposted = []
            counts = [:]
            available = true
        }
        self.me = me
    }

    func reset() {
        me = nil
        reposted = []
        counts = [:]
        available = true
    }

    func isReposted(_ id: UUID) -> Bool { reposted.contains(id) }
    func count(for id: UUID) -> Int { counts[id] ?? 0 }

    private struct CountRow: Decodable {
        let asset_id: UUID
        let repost_count: Int
    }

    private struct ToggleParams: Encodable {
        let p_asset: String
        let p_caption: String?
    }

    private struct CountParams: Encodable {
        let p_assets: [String]
    }

    func prime(_ assets: [DigitalAsset]) async {
        guard available, let me, !assets.isEmpty else { return }
        let ids = assets.map(\.id)
        do {
            let rows: [CountRow] = try await client
                .rpc("get_repost_counts", params: CountParams(
                    p_assets: ids.map { $0.uuidString.lowercased() }))
                .execute()
                .value
            for r in rows { counts[r.asset_id] = r.repost_count }

            struct Mine: Decodable { let asset_id: UUID }
            let mine: [Mine] = try await client
                .from("reposts")
                .select("asset_id")
                .eq("user_id", value: me)
                .in("asset_id", values: ids.map(\.uuidString))
                .execute()
                .value
            for m in mine { reposted.insert(m.asset_id) }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    @discardableResult
    func toggle(_ asset: DigitalAsset) async -> Bool {
        guard me != nil else { return false }
        let id = asset.id
        let was = reposted.contains(id)
        // Optimistic
        if was {
            reposted.remove(id)
            counts[id] = max(0, (counts[id] ?? 1) - 1)
        } else {
            reposted.insert(id)
            counts[id] = (counts[id] ?? 0) + 1
        }
        do {
            let nowOn: Bool = try await client
                .rpc("toggle_repost", params: ToggleParams(
                    p_asset: id.uuidString.lowercased(), p_caption: nil))
                .execute()
                .value
            if nowOn {
                reposted.insert(id)
                ProgressStore.shared.noteQuest(kind: "repost")
            } else {
                reposted.remove(id)
            }
            return nowOn
        } catch {
            // Roll back
            if was {
                reposted.insert(id)
                counts[id] = (counts[id] ?? 0) + 1
            } else {
                reposted.remove(id)
                counts[id] = max(0, (counts[id] ?? 1) - 1)
            }
            if EngagementStore.isMissingSchema(error) { available = false }
            return was
        }
    }
}
