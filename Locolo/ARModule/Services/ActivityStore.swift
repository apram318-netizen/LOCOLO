//
//  ActivityStore.swift
//  Locolo
//
//  The notifications-style activity feed: new followers, hypes, comments and
//  offers on the user's creations. Aggregated client-side from the existing
//  tables (RLS already scopes each to rows the user may read), so it needs no
//  extra backend. "Unread" is anything newer than the last time the activity
//  screen was opened.
//

import Foundation
import Combine
import Supabase

struct SocialActivity: Identifiable, Hashable {
    enum Kind: Hashable {
        case follow
        case hype
        case comment(String)
        case offer(amount: Double, status: String)
    }

    let id: String
    let kind: Kind
    let actorId: UUID
    let asset: ActivityAssetRef?
    let date: Date?
}

struct ActivityAssetRef: Hashable, Decodable {
    let id: UUID
    let name: String?
    let thumbUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "asset_id"
        case name
        case thumbUrl = "thumb_url"
    }
}

@MainActor
final class ActivityStore: ObservableObject {
    static let shared = ActivityStore()

    @Published private(set) var items: [SocialActivity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var lastSeen: Date

    private let client = SupabaseManager.shared.client
    private var me: UUID?
    private let seenKey = "ar.activity.lastSeen"
    private var lastRefresh: Date?

    private init() {
        let t = UserDefaults.standard.double(forKey: seenKey)
        lastSeen = t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    func configure(me: UUID) {
        if self.me != me {
            items = []
            hasLoaded = false
            lastRefresh = nil
        }
        self.me = me
    }

    func reset() {
        me = nil
        items = []
        hasLoaded = false
        lastRefresh = nil
        lastSeen = .distantPast
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    var visibleItems: [SocialActivity] {
        let blocked = SafetyService.shared.blockedUserIds
        return items.filter { !blocked.contains($0.actorId) }
    }

    var unreadCount: Int {
        visibleItems.filter { ($0.date ?? .distantPast) > lastSeen }.count
    }

    func isNew(_ item: SocialActivity) -> Bool {
        (item.date ?? .distantPast) > lastSeen
    }

    func markAllSeen() {
        let newest = items.compactMap(\.date).max() ?? Date()
        lastSeen = max(newest, Date())
        UserDefaults.standard.set(lastSeen.timeIntervalSince1970, forKey: seenKey)
    }

    // MARK: Loading

    private struct FollowerRow: Decodable {
        let follower_id: UUID
        let updated_at: Date?
    }
    private struct HypeRow: Decodable {
        let user_id: UUID
        let asset_id: UUID
        let created_at: Date?
    }
    private struct CommentRow: Decodable {
        let comment_id: UUID
        let user_id: UUID
        let asset_id: UUID
        let body: String
        let created_at: Date
    }
    private struct OfferRow: Decodable {
        let offer_id: UUID
        let buyer_id: UUID
        let asset_id: UUID
        let amount: Double
        let status: String?
        let created_at: Date?
    }

    /// Refreshes the feed; `force: false` skips if refreshed in the last 30s.
    func refresh(force: Bool = true) async {
        guard let me, !isLoading else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
            lastRefresh = Date()
        }

        let myAssets: [ActivityAssetRef] = (try? await client
            .from("digital_assets")
            .select("asset_id, name, thumb_url")
            .eq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(300)
            .execute()
            .value) ?? []
        let assetsById = Dictionary(uniqueKeysWithValues: myAssets.map { ($0.id, $0) })
        let assetIds = myAssets.map(\.id.uuidString)

        async let followers = fetchFollowers(me)
        async let hypes = assetIds.isEmpty ? [] : fetchHypes(assetIds, me: me)
        async let comments = assetIds.isEmpty ? [] : fetchComments(assetIds, me: me)
        async let offers = assetIds.isEmpty ? [] : fetchOffers(assetIds, me: me)

        var built: [SocialActivity] = []
        for f in await followers {
            built.append(SocialActivity(id: "f-\(f.follower_id)", kind: .follow,
                                      actorId: f.follower_id, asset: nil, date: f.updated_at))
        }
        for h in await hypes {
            built.append(SocialActivity(id: "h-\(h.user_id)-\(h.asset_id)", kind: .hype,
                                      actorId: h.user_id, asset: assetsById[h.asset_id], date: h.created_at))
        }
        for c in await comments {
            built.append(SocialActivity(id: "c-\(c.comment_id)", kind: .comment(c.body),
                                      actorId: c.user_id, asset: assetsById[c.asset_id], date: c.created_at))
        }
        for o in await offers {
            built.append(SocialActivity(id: "o-\(o.offer_id)",
                                      kind: .offer(amount: o.amount, status: o.status ?? "pending"),
                                      actorId: o.buyer_id, asset: assetsById[o.asset_id], date: o.created_at))
        }

        built.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        await CreatorCache.shared.load(built.map(\.actorId))
        items = built
    }

    private func fetchFollowers(_ me: UUID) async -> [FollowerRow] {
        (try? await client
            .from("follows")
            .select("follower_id, updated_at")
            .eq("followee_id", value: me)
            .eq("status", value: "accepted")
            .order("updated_at", ascending: false)
            .limit(60)
            .execute()
            .value) ?? []
    }

    private func fetchHypes(_ assetIds: [String], me: UUID) async -> [HypeRow] {
        (try? await client
            .from("asset_hype")
            .select("user_id, asset_id, created_at")
            .in("asset_id", values: assetIds)
            .neq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(80)
            .execute()
            .value) ?? []
    }

    private func fetchComments(_ assetIds: [String], me: UUID) async -> [CommentRow] {
        (try? await client
            .from("asset_comments")
            .select("comment_id, user_id, asset_id, body, created_at")
            .in("asset_id", values: assetIds)
            .neq("user_id", value: me)
            .order("created_at", ascending: false)
            .limit(80)
            .execute()
            .value) ?? []
    }

    private func fetchOffers(_ assetIds: [String], me: UUID) async -> [OfferRow] {
        (try? await client
            .from("offers")
            .select("offer_id, buyer_id, asset_id, amount, status, created_at")
            .in("asset_id", values: assetIds)
            .neq("buyer_id", value: me)
            .order("created_at", ascending: false)
            .limit(40)
            .execute()
            .value) ?? []
    }
}
