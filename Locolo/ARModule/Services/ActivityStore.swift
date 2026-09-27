//
//  ActivityStore.swift
//  Locolo
//
//  The notifications-style activity feed: follows, hypes, comments, mentions,
//  offers, new drops from people you follow, discoveries and milestones.
//
//  Source of truth is the server `notifications` table (filled by database
//  triggers — docs/migrations/2026_ar_notifications.sql), whose read_at makes
//  read state follow the account across devices. Until that migration runs,
//  the feed is aggregated client-side from follows / asset_hype /
//  asset_comments / offers and "unread" is newer than the last visit.
//
//  While the server isn't sending pushes (PushRegistry.serverPushActive),
//  new items also raise local notifications so nothing goes unnoticed.
//

import Foundation
import Combine
import UIKit
import Supabase

struct SocialActivity: Identifiable, Hashable {
    enum Kind: Hashable {
        case follow
        case hype
        case comment(String)
        case mention(String)
        case offer(amount: Double, status: String)
        case offerUpdate(accepted: Bool, amount: Double?)
        case newPost
        case discovery
        case milestone(metric: String, count: Int)
    }

    let id: String
    let kind: Kind
    let actorId: UUID?
    let asset: ActivityAssetRef?
    let date: Date?

    /// The server `type` name (used for notification preferences).
    var typeKey: String {
        switch kind {
        case .follow: return "follow"
        case .hype: return "hype"
        case .comment: return "comment"
        case .mention: return "mention"
        case .offer: return "offer"
        case .offerUpdate: return "offer_status"
        case .newPost: return "new_post"
        case .discovery: return "discovery"
        case .milestone: return "milestone"
        }
    }
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

    enum Source { case unknown, server, legacy }

    @Published private(set) var items: [SocialActivity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var lastSeen: Date
    @Published private(set) var source: Source = .unknown
    /// Server mode: ids whose read_at is still null.
    @Published private var serverUnread: Set<String> = []
    /// Suppresses local alerts while the Activity screen is on screen.
    var isViewing = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?
    private let seenKey = "ar.activity.lastSeen"
    private let alertedKey = "ar.activity.lastAlerted"
    private var lastRefresh: Date?

    private init() {
        let t = UserDefaults.standard.double(forKey: seenKey)
        lastSeen = t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    func configure(me: UUID) {
        if self.me != me {
            items = []
            serverUnread = []
            hasLoaded = false
            lastRefresh = nil
            source = .unknown
        }
        self.me = me
    }

    func reset() {
        me = nil
        items = []
        serverUnread = []
        hasLoaded = false
        lastRefresh = nil
        source = .unknown
        isViewing = false
        lastSeen = .distantPast
        UserDefaults.standard.removeObject(forKey: seenKey)
        UserDefaults.standard.removeObject(forKey: alertedKey)
    }

    var visibleItems: [SocialActivity] {
        let blocked = SafetyService.shared.blockedUserIds
        return items.filter { item in
            guard let actor = item.actorId else { return true }
            return !blocked.contains(actor)
        }
    }

    var unreadCount: Int {
        visibleItems.filter(isNew).count
    }

    func isNew(_ item: SocialActivity) -> Bool {
        if source == .server { return serverUnread.contains(item.id) }
        return (item.date ?? .distantPast) > lastSeen
    }

    func markAllSeen() {
        let newest = items.compactMap(\.date).max() ?? Date()
        lastSeen = max(newest, Date())
        UserDefaults.standard.set(lastSeen.timeIntervalSince1970, forKey: seenKey)

        guard source == .server, let me, !serverUnread.isEmpty else { return }
        serverUnread = []
        Task { [client] in
            _ = try? await client
                .from("notifications")
                .update(["read_at": ISO8601DateFormatter().string(from: Date())])
                .eq("recipient_id", value: me)
                .is("read_at", value: nil)
                .neq("type", value: "message")
                .execute()
        }
    }

    /// Clears one item (swipe to delete). Server mode deletes the row.
    func remove(_ item: SocialActivity) {
        items.removeAll { $0.id == item.id }
        serverUnread.remove(item.id)
        guard source == .server else { return }
        Task { [client] in
            _ = try? await client.from("notifications").delete()
                .eq("notification_id", value: item.id)
                .execute()
        }
    }

    // MARK: Loading

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

        var built: [SocialActivity]?
        if source != .legacy {
            switch await fetchServer(me) {
            case .success(let result):
                source = .server
                serverUnread = result.unread
                built = result.items
            case .failure(let error):
                if EngagementStore.isMissingSchema(error) {
                    source = .legacy
                } else if source == .server {
                    return
                }
            }
        }
        if built == nil {
            if source == .unknown { source = .legacy }
            built = await fetchLegacy(me)
        }
        guard let built, self.me == me else { return }

        await CreatorCache.shared.load(built.compactMap(\.actorId))
        items = built
        await alertIfNeeded()
    }

    // MARK: Server feed

    private struct NotificationRow: Decodable {
        let notification_id: UUID
        let actor_id: UUID?
        let type: String
        let body: String?
        let created_at: Date
        let read_at: Date?
        let digital_assets: ActivityAssetRef?
    }

    private struct ServerResult {
        let items: [SocialActivity]
        let unread: Set<String>
    }

    private func fetchServer(_ me: UUID) async -> Result<ServerResult, Error> {
        do {
            let rows: [NotificationRow] = try await client
                .from("notifications")
                .select("notification_id, actor_id, type, body, created_at, read_at, digital_assets(asset_id, name, thumb_url)")
                .eq("recipient_id", value: me)
                .neq("type", value: "message")
                .order("created_at", ascending: false)
                .limit(120)
                .execute()
                .value
            var unread: Set<String> = []
            let items: [SocialActivity] = rows.compactMap { row in
                guard let kind = Self.kind(type: row.type, body: row.body) else { return nil }
                let id = row.notification_id.uuidString.lowercased()
                if row.read_at == nil { unread.insert(id) }
                return SocialActivity(id: id, kind: kind, actorId: row.actor_id,
                                      asset: row.digital_assets, date: row.created_at)
            }
            return .success(ServerResult(items: items, unread: unread))
        } catch {
            return .failure(error)
        }
    }

    private static func kind(type: String, body: String?) -> SocialActivity.Kind? {
        let text = body ?? ""
        switch type {
        case "follow": return .follow
        case "hype": return .hype
        case "comment": return .comment(text)
        case "mention": return .mention(text)
        case "offer": return .offer(amount: Double(text) ?? 0, status: "pending")
        case "offer_status":
            let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
            return .offerUpdate(accepted: parts.first == "accepted",
                                amount: parts.count > 1 ? Double(parts[1]) : nil)
        case "new_post": return .newPost
        case "discovery": return .discovery
        case "milestone":
            let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let count = Int(parts[1]) else { return nil }
            return .milestone(metric: parts[0], count: count)
        default: return nil
        }
    }

    // MARK: Legacy client-side aggregation

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

    private func fetchLegacy(_ me: UUID) async -> [SocialActivity] {
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
        return built
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

    // MARK: Local alerts (until server push is live)

    private func alertIfNeeded() async {
        let defaults = UserDefaults.standard
        let newest = items.compactMap(\.date).max() ?? Date()
        let lastAlerted = defaults.double(forKey: alertedKey)
        defer { defaults.set(max(newest.timeIntervalSince1970, lastAlerted), forKey: alertedKey) }

        // First load on this device: everything already there is backlog.
        guard lastAlerted > 0 else { return }
        guard !PushRegistry.shared.serverPushActive, !isViewing else { return }

        let prefs = NotificationPreferences.shared.prefs
        let fresh = visibleItems.filter { item in
            guard let date = item.date, date.timeIntervalSince1970 > lastAlerted + 0.5 else { return false }
            return isNew(item) && prefs.allows(type: item.typeKey)
        }
        guard !fresh.isEmpty else { return }

        if fresh.count > 3 {
            await ARNotificationRouter.post(.init(
                id: "activity-summary",
                title: "Locolo",
                body: "You have \(fresh.count) new notifications — follows, hypes and comments are waiting.",
                url: URL(string: "locolo://activity"),
                thread: "activity",
                type: "summary"))
            return
        }
        for item in fresh.reversed() {
            let copy = localCopy(for: item)
            await ARNotificationRouter.post(.init(
                id: "activity-\(item.id)",
                title: copy.title,
                subtitle: copy.subtitle,
                body: copy.body,
                url: copy.url,
                thread: copy.thread,
                type: item.typeKey,
                imageURL: item.asset?.thumbUrl.flatMap(URL.init(string:))))
        }
    }

    private func localCopy(for item: SocialActivity)
        -> (title: String, subtitle: String?, body: String, url: URL?, thread: String) {
        let actor = item.actorId.flatMap { CreatorCache.shared.creator($0) }
        let who = actor?.displayName ?? "Someone"
        let handle = actor.map { "@\($0.username)" }
        let art = item.asset?.name.map { "“\($0)”" } ?? "your creation"
        let assetURL = item.asset.map { DeepLinkRouter.assetURL(for: $0.id) }
        let userURL = item.actorId.map { DeepLinkRouter.userURL(for: $0) }
        let assetThread = item.asset.map { "asset-\($0.id.uuidString.lowercased())" } ?? "activity"

        switch item.kind {
        case .follow:
            return (who, handle, "started following you.", userURL, "follows")
        case .hype:
            return ("⚡ \(who) hyped \(art)", nil, "Your creation is getting noticed.", assetURL, assetThread)
        case .comment(let body):
            return ("\(who) commented on \(art)", nil, "“\(body.prefix(140))”", assetURL, assetThread)
        case .mention(let body):
            return ("\(who) mentioned you", nil, "“\(body.prefix(140))”", assetURL, assetThread)
        case .offer(let amount, _):
            return ("💰 New offer: \(amount.formatted(.currency(code: "USD")))", nil,
                    "\(who) wants to buy \(art). Tap to review.", assetURL, "offers")
        case .offerUpdate(let accepted, let amount):
            let offer = amount.map { "your \($0.formatted(.currency(code: "USD"))) offer" } ?? "your offer"
            return accepted
                ? ("🎉 Offer accepted", nil, "\(who) accepted \(offer) for \(art).", assetURL, "offers")
                : ("Offer declined", nil, "\(who) declined \(offer) for \(art).", assetURL, "offers")
        case .newPost:
            return ("✨ \(who) dropped something new", nil, "\(art) is live — go find it in AR.", assetURL, "new-posts")
        case .discovery:
            return ("🧭 \(who) discovered \(art)", nil, "Someone just found your creation in the wild.", assetURL, assetThread)
        case .milestone(let metric, let count):
            return metric == "views"
                ? ("👀 \(count) explorers found \(art)", nil, "Your creation is a local landmark.", assetURL, "milestones")
                : ("🔥 \(art) hit \(count) hypes", nil, "Keep creating — people love this one.", assetURL, "milestones")
        }
    }
}
