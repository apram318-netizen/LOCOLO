//
//  ARProfileViewModel.swift
//  Locolo
//
//  Backs the AR Creator Dashboard: the user's own digital assets, the
//  assets they've explored in AR sessions, and marketplace data (offers
//  received, revenue, portfolio value) plus the aggregates the analytics
//  charts draw from. No posts/places here — that stays in the main app.
//

import Foundation
import Supabase

@MainActor
final class ARProfileViewModel: ObservableObject {
    @Published var ownAssets: [DigitalAsset] = []
    @Published var exploredAssets: [DigitalAsset] = []
    /// Last-seen date per explored asset (Explorer Passport streaks).
    @Published var exploredDates: [Date] = []
    @Published var offersByAsset: [UUID: [Offer]] = [:]
    @Published var portfolioSnapshots: [PortfolioSnapshot] = []
    @Published var isLoading = false
    @Published var isLoadingOffers = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client
    private let assetRepo = DigitalAssetRepository()
    private let marketplaceRepo = MarketplaceRepository.shared

    // MARK: - Overview stats

    var totalViews: Int { ownAssets.reduce(0) { $0 + $1.viewCount } }
    var totalHype: Int { ownAssets.reduce(0) { $0 + $1.hypeCount } }

    var topAsset: DigitalAsset? {
        ownAssets.max { $0.engagementScore < $1.engagementScore }
    }

    // MARK: - Marketplace insights

    var allOffers: [Offer] { offersByAsset.values.flatMap { $0 } }

    var pendingOffers: [Offer] { allOffers.filter { $0.status == "pending" } }

    /// Sum of accepted offers — realised earnings.
    var revenue: Double {
        allOffers.filter { $0.status == "accepted" }.reduce(0) { $0 + $1.price }
    }

    /// Latest portfolio snapshot when available; otherwise sum of listed
    /// values on your creations (until holdings-by-owner fully replaces it).
    var portfolioValue: Double {
        if let latest = portfolioSnapshots.max(by: { $0.day < $1.day }) {
            return latest.totalValue
        }
        return ownAssets.reduce(0) { $0 + ($1.currentValue ?? 0) }
    }

    var highestOpenOffer: Double? {
        pendingOffers.map(\.price).max()
    }

    /// Assets that have at least one pending offer, best offer first.
    var assetsWithPendingOffers: [(asset: DigitalAsset, best: Double, count: Int)] {
        ownAssets.compactMap { asset in
            let pending = (offersByAsset[asset.id] ?? []).filter { $0.status == "pending" }
            guard let best = pending.map(\.price).max() else { return nil }
            return (asset: asset, best: best, count: pending.count)
        }
        .sorted { $0.best > $1.best }
    }

    // MARK: - Analytics aggregates

    /// Top assets by view count, for the horizontal bar chart.
    var topAssetsByViews: [(name: String, views: Int)] {
        ownAssets
            .sorted { $0.viewCount > $1.viewCount }
            .prefix(5)
            .map { (name: $0.name ?? "Untitled", views: $0.viewCount) }
    }

    /// Uploads bucketed by month, oldest first, for the area chart.
    var uploadsByMonth: [(month: Date, count: Int)] {
        let calendar = Calendar.current
        var buckets: [Date: Int] = [:]
        for asset in ownAssets {
            let comps = calendar.dateComponents([.year, .month], from: asset.createdAt)
            if let month = calendar.date(from: comps) {
                buckets[month, default: 0] += 1
            }
        }
        return buckets.sorted { $0.key < $1.key }
            .map { (month: $0.key, count: $0.value) }
    }

    /// Fixed category order so chart colors stay stable per category
    /// regardless of which categories the user currently has.
    static let categoryOrder = ["art", "photo", "3d", "audio", "other"]

    /// Own assets per category, in the fixed canonical order.
    var categoryBreakdown: [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for asset in ownAssets {
            var cat = asset.normalizedCategory ?? "other"
            if !ARProfileViewModel.categoryOrder.contains(cat) { cat = "other" }
            counts[cat, default: 0] += 1
        }
        return ARProfileViewModel.categoryOrder.compactMap { cat in
            guard let count = counts[cat] else { return nil }
            return (category: cat, count: count)
        }
    }

    // MARK: - Loading

    func load(userId: UUID) async {
        isLoading = ownAssets.isEmpty
        errorMessage = nil

        do {
            async let own: [DigitalAsset] = client
                .from("digital_assets")
                .select("*")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            async let seen = SeenAssetsRepository.shared.fetchSeenHistory(userId: userId)

            ownAssets = try await own
            // Your own assets don't belong in "Explored"
            let history = try await seen.filter { $0.asset.userId != userId }
            exploredAssets = history.map(\.asset)
            exploredDates = history.map(\.seenAt)
        } catch {
            errorMessage = "Failed to load profile: \(error.localizedDescription)"
        }
        isLoading = false

        await loadOffers()
        await loadPortfolioSnapshots(userId: userId)
    }

    /// Fetch offers for every asset that accepts them, concurrently.
    private func loadOffers() async {
        let offerable = ownAssets.filter { $0.acceptsOffers == true || $0.isForSale == true }
        guard !offerable.isEmpty else {
            offersByAsset = [:]
            return
        }

        isLoadingOffers = true
        var result: [UUID: [Offer]] = [:]

        await withTaskGroup(of: (UUID, [Offer]).self) { group in
            for asset in offerable {
                group.addTask { [assetRepo] in
                    let offers = (try? await assetRepo.fetchOffers(for: asset.id)) ?? []
                    return (asset.id, offers)
                }
            }
            for await (id, offers) in group {
                result[id] = offers
            }
        }

        offersByAsset = result
        isLoadingOffers = false
    }

    private func loadPortfolioSnapshots(userId: UUID) async {
        var snapshots = (try? await marketplaceRepo.portfolioSnapshots(for: userId, limit: 90)) ?? []

        if snapshots.isEmpty {
            if let holdings = try? await fetchHoldings(userId: userId) {
                let total = holdings.reduce(0) { $0 + ($1.currentValue ?? 0) }
                try? await marketplaceRepo.recordPortfolioSnapshot(
                    userId: userId,
                    total: total,
                    holdings: holdings.count
                )
                snapshots = (try? await marketplaceRepo.portfolioSnapshots(for: userId, limit: 90)) ?? []
            }
        }

        portfolioSnapshots = snapshots
    }

    private func fetchHoldings(userId: UUID) async throws -> [DigitalAsset] {
        try await client
            .from("digital_assets")
            .select("*")
            .eq("owner_id", value: userId)
            .execute()
            .value
    }
}
