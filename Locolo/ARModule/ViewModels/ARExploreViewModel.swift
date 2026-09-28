//
//  ARExploreViewModel.swift
//  Locolo
//
//  Backs the Explore tab of the AR dashboard: featured carousel, the
//  social feed (For You / Trending / Nearby), creator info for the feed
//  cards, and client-side paging for infinite scrolling.
//

import Foundation
import Combine
import Supabase
import CoreLocation

// ARCreator now lives in Models/ARCreator.swift (shared with profiles). (WS4)

// MARK: - View model

@MainActor
final class ARExploreViewModel: ObservableObject {

    enum FeedFilter: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case following = "Following"
        case trending = "Trending"
        case nearby = "Nearby"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .forYou: return "wand.and.stars"
            case .following: return "person.2"
            case .trending: return "flame"
            case .nearby: return "location"
            }
        }
    }

    struct SuggestedCreator: Identifiable {
        let creator: ARCreator
        let assetCount: Int
        let totalHype: Int
        let preview: DigitalAsset?
        var id: UUID { creator.id }
    }

    @Published var featuredAssets: [DigitalAsset] = []
    /// Server-ranked personalized feed from get_recommended_assets (WS5).
    /// Empty until loaded / when unavailable — the For You filter falls back
    /// to a newest-first client sort in that case.
    @Published var recommendedAssets: [DigitalAsset] = []
    @Published var creators: [UUID: ARCreator] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var feedFilter: FeedFilter = .forYou {
        didSet { visibleCount = ARExploreViewModel.pageSize }
    }
    @Published private(set) var visibleCount = ARExploreViewModel.pageSize

    private static let pageSize = 8

    private var allAssets: [DigitalAsset] = []
    /// Top slice by engagement — used for the "Trending" badge on cards.
    private(set) var trendingIds: Set<UUID> = []

    private let repo = DigitalAssetRepository()
    private let client = SupabaseManager.shared.client
    private var observers: Set<AnyCancellable> = []

    init() {
        // Blocking/reporting must drop content from the feed immediately, and
        // follow changes reshape the Following feed + suggestions.
        SafetyService.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
        FollowStore.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
        SafetyExtrasStore.shared.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &observers)
    }

    private var myId: UUID? {
        SupabaseManager.shared.currentUserId.flatMap(UUID.init(uuidString:))
    }

    /// Creators with visible work that the user doesn't follow yet, ranked by
    /// total hype and output — the "Creators to follow" rail.
    var suggestedCreators: [SuggestedCreator] {
        let following = FollowStore.shared.following
        let me = myId
        let grouped = Dictionary(grouping: SafetyService.shared.visible(allAssets), by: \.userId)
        let list: [SuggestedCreator] = grouped.compactMap { uid, assets in
            guard uid != me, !following.contains(uid), let creator = creators[uid] else { return nil }
            return SuggestedCreator(
                creator: creator,
                assetCount: assets.count,
                totalHype: assets.reduce(0) { $0 + $1.hypeCount },
                preview: assets.max { $0.engagementScore < $1.engagementScore }
            )
        }
        return Array(list
            .sorted { ($0.totalHype + $0.assetCount * 3) > ($1.totalHype + $1.assetCount * 3) }
            .prefix(10))
    }

    // MARK: Feed

    /// Featured carousel minus blocked/reported content.
    var visibleFeatured: [DigitalAsset] {
        SafetyService.shared.visible(featuredAssets)
    }

    /// The full feed for the active filter.
    var feedAssets: [DigitalAsset] {
        let muted = SafetyExtrasStore.shared.muted
        let base = SafetyService.shared.visible(allAssets)
            .filter { !muted.contains($0.userId) }
        switch feedFilter {
        case .forYou:
            // Prefer the server-ranked personalized feed; fall back to newest.
            let recs = SafetyService.shared.visible(recommendedAssets)
                .filter { !muted.contains($0.userId) }
            return recs.isEmpty
                ? base.sorted { $0.createdAt > $1.createdAt }
                : recs
        case .following:
            let following = FollowStore.shared.following
            return base
                .filter { following.contains($0.userId) }
                .sorted { $0.createdAt > $1.createdAt }
        case .trending:
            return base.sorted { $0.engagementScore > $1.engagementScore }
        case .nearby:
            // Assets with a known distance first, closest to farthest.
            return base.sorted {
                ($0.distanceMeters ?? .greatestFiniteMagnitude) <
                ($1.distanceMeters ?? .greatestFiniteMagnitude)
            }
        }
    }

    /// Nearby ∩ high engagement — “Trending near you” rail.
    var trendingNearYou: [DigitalAsset] {
        let muted = SafetyExtrasStore.shared.muted
        return SafetyService.shared.visible(allAssets)
            .filter { !muted.contains($0.userId) }
            .filter { ($0.distanceMeters ?? .infinity) < 2_000 }
            .sorted { $0.engagementScore > $1.engagementScore }
            .prefix(12)
            .map { $0 }
    }

    /// Created today — “Drops today” rail.
    var dropsToday: [DigitalAsset] {
        let muted = SafetyExtrasStore.shared.muted
        let cal = Calendar.current
        return SafetyService.shared.visible(allAssets)
            .filter { !muted.contains($0.userId) }
            .filter { cal.isDateInToday($0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(12)
            .map { $0 }
    }

    /// The slice currently rendered; grows as the user scrolls.
    var visibleFeed: [DigitalAsset] {
        Array(feedAssets.prefix(visibleCount))
    }

    var hasMore: Bool { visibleCount < feedAssets.count }

    func loadMoreIfNeeded(current asset: DigitalAsset) {
        guard hasMore, asset.id == visibleFeed.last?.id else { return }
        visibleCount += ARExploreViewModel.pageSize
    }

    func isTrending(_ asset: DigitalAsset) -> Bool {
        trendingIds.contains(asset.id)
    }

    func creator(for asset: DigitalAsset) -> ARCreator? {
        creators[asset.userId]
    }

    // MARK: Loading

    /// Shows the local cache instantly, then replaces it with fresh server data.
    /// `refresh()` (pull-to-refresh) skips straight to the network.
    func load() async {
        isLoading = allAssets.isEmpty
        errorMessage = nil

        let cached = await repo.fetchAll()
        if !cached.isEmpty { apply(cached) }
        isLoading = false

        await refresh()
    }

    func refresh() async {
        let fresh = await repo.fetchAll(forceRefresh: true)
        if !fresh.isEmpty {
            apply(fresh)
            errorMessage = nil
        } else if allAssets.isEmpty {
            // fetchAll returns [] only when both the network and cache came
            // back empty; distinguish "offline" from "nothing posted yet".
            errorMessage = await isReachable()
                ? nil
                : "Can't reach Locolo right now. Pull to retry."
        }
        isLoading = false

        await loadRecommended()
        await loadCreators(for: allAssets)
    }

    private func apply(_ assets: [DigitalAsset]) {
        allAssets = assets
        let byEngagement = assets.sorted { $0.engagementScore > $1.engagementScore }
        featuredAssets = Array(byEngagement.prefix(6))
        // Top quarter of assets (at least the featured ones) count as trending.
        let trendingSlice = byEngagement.prefix(max(6, assets.count / 4))
        trendingIds = Set(trendingSlice.map(\.id))
    }

    private func isReachable() async -> Bool {
        do {
            _ = try await client.from("digital_assets").select("asset_id").limit(1).execute()
            return true
        } catch {
            return false
        }
    }

    // MARK: Personalized feed (WS5)

    private struct RecParams: Encodable {
        let p_user: String
        let p_lat: Double
        let p_lon: Double
        let p_radius_meters: Double
        let p_limit: Int
    }

    /// Server-ranked "For You" via get_recommended_assets. Needs a signed-in
    /// user and a location; otherwise (or on error) we leave recommendedAssets
    /// empty and the feed falls back to a newest-first sort.
    private func loadRecommended() async {
        guard
            let idString = SupabaseManager.shared.currentUserId,
            let userId = UUID(uuidString: idString)
        else { return }

        let manager = LocationManager.shared
        guard let coord = manager.userLocation ?? manager.latestStoredLocation else { return }

        do {
            let recs: [DigitalAsset] = try await client
                .rpc("get_recommended_assets", params: RecParams(
                    p_user: userId.uuidString,
                    p_lat: coord.latitude,
                    p_lon: coord.longitude,
                    p_radius_meters: 50_000,
                    p_limit: 60
                ))
                .execute()
                .value
            recommendedAssets = recs
            // Fold any creators we don't already have into the cache.
            await loadCreators(for: recs)
        } catch {
            // Non-fatal: For You just falls back to the newest-first sort.
            print("Recommended feed fetch failed:", error.localizedDescription)
        }
    }

    /// One batched query for every distinct creator in the feed.
    private func loadCreators(for assets: [DigitalAsset]) async {
        let missing = Set(assets.map(\.userId)).subtracting(creators.keys)
        guard !missing.isEmpty else { return }

        do {
            let rows: [ARCreator] = try await client
                .from("users")
                .select("user_id, username, name, avatar_url, verified_flags")
                .in("user_id", values: missing.map(\.uuidString))
                .execute()
                .value

            for row in rows {
                creators[row.id] = row
            }
            CreatorCache.shared.insert(rows)
        } catch {
            // Creator chips just stay hidden; the feed itself is unaffected.
            print("Explore creator fetch failed:", error.localizedDescription)
        }
    }
}
