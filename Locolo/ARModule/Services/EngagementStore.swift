//
//  EngagementStore.swift
//  Locolo
//
//  Single source of truth for hype + comment state across the feed, the
//  detail sheet, profiles and search. Views read counts from here instead of
//  the (possibly stale) DigitalAsset snapshot they were handed, so hyping on
//  a card instantly updates the detail sheet and vice versa.
//

import Foundation
import Combine
import Supabase

@MainActor
final class EngagementStore: ObservableObject {
    static let shared = EngagementStore()

    @Published private(set) var hyped: Set<UUID> = []
    @Published private(set) var hypeCounts: [UUID: Int] = [:]
    @Published private(set) var commentCounts: [UUID: Int] = [:]
    /// False once the server reports the comments schema is missing
    /// (docs/migrations/2026_ar_social.sql not applied yet).
    @Published private(set) var commentsAvailable = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?
    private var primedHype: Set<UUID> = []
    private var primedComments: Set<UUID> = []
    private var toggling: Set<UUID> = []

    private init() {}

    func configure(me: UUID) {
        guard self.me != me else { return }
        reset()
        self.me = me
    }

    func reset() {
        me = nil
        hyped = []
        hypeCounts = [:]
        commentCounts = [:]
        primedHype = []
        primedComments = []
        toggling = []
        commentsAvailable = true
    }

    // MARK: Reads

    func isHyped(_ assetId: UUID) -> Bool { hyped.contains(assetId) }

    func hypeCount(for asset: DigitalAsset) -> Int {
        hypeCounts[asset.id] ?? asset.hypeCount
    }

    func commentCount(for assetId: UUID) -> Int {
        commentCounts[assetId] ?? 0
    }

    // MARK: Priming

    private struct HypeKeyRow: Decodable { let asset_id: UUID }
    private struct CommentCountRow: Decodable {
        let asset_id: UUID
        let comment_count: Int
    }

    /// Batch-loads "did I hype this" + comment counts for assets about to be
    /// shown. Already-primed ids are skipped, so calling this on every feed
    /// page is cheap.
    func prime(_ assets: [DigitalAsset]) async {
        let ids = assets.map(\.id)
        for a in assets where hypeCounts[a.id] == nil { hypeCounts[a.id] = a.hypeCount }

        let hypeIds = ids.filter { !primedHype.contains($0) }
        let commentIds = ids.filter { !primedComments.contains($0) }
        primedHype.formUnion(hypeIds)
        primedComments.formUnion(commentIds)

        async let h: Void = primeHype(hypeIds)
        async let c: Void = primeComments(commentIds)
        _ = await (h, c)
    }

    private func primeHype(_ ids: [UUID]) async {
        guard let me, !ids.isEmpty else { return }
        do {
            let rows: [HypeKeyRow] = try await client
                .from("asset_hype")
                .select("asset_id")
                .eq("user_id", value: me)
                .in("asset_id", values: ids.map(\.uuidString))
                .execute()
                .value
            hyped.formUnion(rows.map(\.asset_id))
        } catch {
            primedHype.subtract(ids)
        }
    }

    private func primeComments(_ ids: [UUID]) async {
        guard commentsAvailable, !ids.isEmpty else { return }
        do {
            let rows: [CommentCountRow] = try await client
                .rpc("get_comment_counts", params: ["p_assets": ids.map(\.uuidString)])
                .execute()
                .value
            for id in ids { commentCounts[id] = 0 }
            for r in rows { commentCounts[r.asset_id] = r.comment_count }
        } catch {
            primedComments.subtract(ids)
            if Self.isMissingSchema(error) { commentsAvailable = false }
        }
    }

    // MARK: Mutations

    /// Optimistic hype toggle. Returns the new hyped state.
    @discardableResult
    func toggleHype(_ asset: DigitalAsset) async -> Bool {
        let id = asset.id
        guard let me, !toggling.contains(id) else { return isHyped(id) }
        toggling.insert(id)
        defer { toggling.remove(id) }

        let wasHyped = hyped.contains(id)
        let oldCount = hypeCount(for: asset)
        apply(hyped: !wasHyped, count: max(0, oldCount + (wasHyped ? -1 : 1)), for: id)

        if let state = await AssetEngagementRepository.shared.toggleHype(userId: me, assetId: id) {
            apply(hyped: state.hyped, count: state.hype_count, for: id)
            if state.hyped && !wasHyped {
                ProgressStore.shared.noteQuest(kind: "hype")
            }
            return state.hyped
        }
        apply(hyped: wasHyped, count: oldCount, for: id)
        return wasHyped
    }

    /// Hype only (never un-hype) — the double-tap gesture.
    func hypeIfNeeded(_ asset: DigitalAsset) async {
        guard !isHyped(asset.id) else { return }
        await toggleHype(asset)
    }

    func adjustCommentCount(by delta: Int, for assetId: UUID) {
        commentCounts[assetId] = max(0, commentCount(for: assetId) + delta)
    }

    func setCommentCount(_ count: Int, for assetId: UUID) {
        commentCounts[assetId] = count
        primedComments.insert(assetId)
    }

    func markCommentsUnavailable() { commentsAvailable = false }

    private func apply(hyped isOn: Bool, count: Int, for id: UUID) {
        if isOn { hyped.insert(id) } else { hyped.remove(id) }
        hypeCounts[id] = count
    }

    /// PostgREST "relation/function does not exist" — the social migration
    /// hasn't been applied to this project yet.
    nonisolated static func isMissingSchema(_ error: Error) -> Bool {
        if let pg = error as? PostgrestError,
           let code = pg.code,
           ["PGRST202", "PGRST205", "42P01", "42883"].contains(code) {
            return true
        }
        let text = String(describing: error).lowercased()
        return text.contains("does not exist") || text.contains("could not find")
    }
}
