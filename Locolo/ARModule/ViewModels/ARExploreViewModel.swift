//
//  ARExploreViewModel.swift
//  Locolo
//
//  Backs the Explore tab of the AR dashboard: featured carousel, the
//  social feed (For You / Trending / Nearby), creator info for the feed
//  cards, and client-side paging for infinite scrolling.
//

import Foundation
import Supabase

// MARK: - Creator (lightweight user row for feed cards)

struct ARCreator: Codable, Identifiable {
    let id: UUID
    let username: String
    let name: String?
    let avatarUrl: URL?
    let verifiedFlags: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case name
        case avatarUrl = "avatar_url"
        case verifiedFlags = "verified_flags"
    }

    var isVerified: Bool { verifiedFlags?["blue"] == true }
    var displayName: String { name ?? username }
}

// MARK: - View model

@MainActor
final class ARExploreViewModel: ObservableObject {

    enum FeedFilter: String, CaseIterable, Identifiable {
        case forYou = "For You"
        case trending = "Trending"
        case nearby = "Nearby"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .forYou: return "wand.and.stars"
            case .trending: return "flame"
            case .nearby: return "location"
            }
        }
    }

    @Published var featuredAssets: [DigitalAsset] = []
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

    // MARK: Feed

    /// The full feed for the active filter.
    var feedAssets: [DigitalAsset] {
        switch feedFilter {
        case .forYou:
            return allAssets.sorted { $0.createdAt > $1.createdAt }
        case .trending:
            return allAssets.sorted { $0.engagementScore > $1.engagementScore }
        case .nearby:
            // Assets with a known distance first, closest to farthest.
            return allAssets.sorted {
                ($0.distanceMeters ?? .greatestFiniteMagnitude) <
                ($1.distanceMeters ?? .greatestFiniteMagnitude)
            }
        }
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

    func load() async {
        isLoading = allAssets.isEmpty
        errorMessage = nil

        allAssets = await repo.fetchAll()

        let byEngagement = allAssets.sorted { $0.engagementScore > $1.engagementScore }
        featuredAssets = Array(byEngagement.prefix(6))
        // Top quarter of assets (at least the featured ones) count as trending.
        let trendingSlice = byEngagement.prefix(max(6, allAssets.count / 4))
        trendingIds = Set(trendingSlice.map(\.id))

        isLoading = false

        await loadCreators(for: allAssets)
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
        } catch {
            // Creator chips just stay hidden; the feed itself is unaffected.
            print("Explore creator fetch failed:", error.localizedDescription)
        }
    }
}
