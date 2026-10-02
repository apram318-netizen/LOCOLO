//
//  MemoryStore.swift
//  Locolo
//
//  "Memos": photos / clips captured in an AR session with an asset. Every
//  asset collects memories; shared ones power the Reels-style swipe feed, the
//  snap-style viewer, the asset sheet and the profile Memories tab.
//
//  Server: docs/migrations/2026_v3_memories_posts_growth.sql (get_memories RPC,
//  asset_memories / memory_likes / memory_views). Degrades to empty lists with
//  `available = false` until that migration is applied.
//

import Foundation
import Combine
import Supabase
import UIKit
import AVFoundation

struct AssetMemory: Identifiable, Hashable, Decodable {
    let id: UUID
    let assetId: UUID
    let userId: UUID
    let mediaUrl: String
    let mediaType: String
    let thumbUrl: String?
    let caption: String?
    let visibility: String
    let sharedToFeed: Bool
    let durationS: Double?
    let createdAt: Date
    var likeCount: Int
    var likedByMe: Bool
    var seenByMe: Bool
    let assetName: String?
    let assetThumbUrl: String?
    let assetOwnerId: UUID?
    let latitude: Double?
    let longitude: Double?

    var isVideo: Bool { mediaType == "video" }
    var previewURL: URL? { URL(string: thumbUrl ?? (isVideo ? (assetThumbUrl ?? "") : mediaUrl)) }

    enum CodingKeys: String, CodingKey {
        case id = "memory_id", assetId = "asset_id", userId = "user_id"
        case mediaUrl = "media_url", mediaType = "media_type", thumbUrl = "thumb_url"
        case caption, visibility, sharedToFeed = "shared_to_feed", durationS = "duration_s"
        case createdAt = "created_at", likeCount = "like_count", likedByMe = "liked_by_me"
        case seenByMe = "seen_by_me", assetName = "asset_name", assetThumbUrl = "asset_thumb_url"
        case assetOwnerId = "asset_owner_id", latitude, longitude
    }
}

@MainActor
final class MemoryStore: ObservableObject {
    static let shared = MemoryStore()

    @Published private(set) var feed: [AssetMemory] = []
    @Published private(set) var byAsset: [UUID: [AssetMemory]] = [:]
    @Published private(set) var byUser: [UUID: [AssetMemory]] = [:]
    @Published private(set) var available = true
    @Published private(set) var isLoadingFeed = false
    @Published private(set) var feedExhausted = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me { reset() }
        self.me = me
    }

    func reset() {
        me = nil
        feed = []
        byAsset = [:]
        byUser = [:]
        available = true
        isLoadingFeed = false
        feedExhausted = false
    }

    // MARK: - Reads

    private struct Params: Encodable {
        let p_scope: String
        let p_id: UUID?
        let p_limit: Int
        let p_before: Date?
    }

    private func fetch(scope: String, id: UUID?, limit: Int = 30, before: Date? = nil) async -> [AssetMemory]? {
        do {
            let rows: [AssetMemory] = try await client
                .rpc("get_memories", params: Params(p_scope: scope, p_id: id, p_limit: limit, p_before: before))
                .execute()
                .value
            available = true
            let visible = rows.filter { !SafetyService.shared.blockedUserIds.contains($0.userId) }
            await CreatorCache.shared.load(Array(Set(visible.map(\.userId))))
            return visible
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            LocoloLog.social.error("get_memories(\(scope, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func refreshFeed() async {
        guard !isLoadingFeed else { return }
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        if let rows = await fetch(scope: "feed", id: nil) {
            feed = rows
            feedExhausted = rows.count < 30
        }
    }

    func loadMoreFeed() async {
        guard !isLoadingFeed, !feedExhausted, let last = feed.last else { return }
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        if let rows = await fetch(scope: "feed", id: nil, before: last.createdAt) {
            let known = Set(feed.map(\.id))
            feed.append(contentsOf: rows.filter { !known.contains($0.id) })
            feedExhausted = rows.count < 30
        }
    }

    @discardableResult
    func load(asset: UUID) async -> [AssetMemory] {
        if let rows = await fetch(scope: "asset", id: asset, limit: 60) {
            byAsset[asset] = rows
        }
        return byAsset[asset] ?? []
    }

    @discardableResult
    func load(user: UUID) async -> [AssetMemory] {
        if let rows = await fetch(scope: "user", id: user, limit: 60) {
            byUser[user] = rows
        }
        return byUser[user] ?? []
    }

    func memory(_ id: UUID) -> AssetMemory? {
        if let m = feed.first(where: { $0.id == id }) { return m }
        for list in byAsset.values { if let m = list.first(where: { $0.id == id }) { return m } }
        for list in byUser.values { if let m = list.first(where: { $0.id == id }) { return m } }
        return nil
    }

    func fetchOne(_ id: UUID) async -> AssetMemory? {
        if let cached = memory(id) { return cached }
        // No single-row RPC: memories are small, read the row then its asset scope.
        struct Row: Decodable { let asset_id: UUID }
        guard let row: Row = try? await client.from("asset_memories")
            .select("asset_id").eq("memory_id", value: id).single().execute().value else { return nil }
        return await load(asset: row.asset_id).first { $0.id == id }
    }

    // MARK: - Writes

    /// Uploads a captured photo / clip and records it against `assetId`.
    @discardableResult
    func create(assetId: UUID, media: Data, isVideo: Bool, caption: String?,
                visibility: String = "public", shareToFeed: Bool = true,
                duration: Double? = nil) async throws -> AssetMemory {
        guard let me else {
            throw NSError(domain: "Memories", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in to save memories."])
        }
        let base = "memories/\(me.uuidString.lowercased())/\(UUID().uuidString.lowercased())"
        let mediaURL = try await ObjStorageManager.shared.uploadFile(
            path: base + (isVideo ? ".mp4" : ".jpg"), fileData: media,
            contentType: isVideo ? "video/mp4" : "image/jpeg")

        var thumbURL: String?
        if isVideo, let poster = await Self.posterFrame(for: media),
           let jpeg = poster.jpegData(compressionQuality: 0.7) {
            thumbURL = try? await ObjStorageManager.shared.uploadFile(
                path: base + "_thumb.jpg", fileData: jpeg, contentType: "image/jpeg")
        }

        struct Insert: Encodable {
            let asset_id: UUID
            let user_id: UUID
            let media_url: String
            let media_type: String
            let thumb_url: String?
            let caption: String?
            let visibility: String
            let shared_to_feed: Bool
            let duration_s: Double?
        }
        let trimmed = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        struct Created: Decodable { let memory_id: UUID }
        let created: Created = try await client.from("asset_memories")
            .insert(Insert(asset_id: assetId, user_id: me, media_url: mediaURL,
                           media_type: isVideo ? "video" : "image", thumb_url: thumbURL,
                           caption: (trimmed?.isEmpty == false) ? trimmed : nil,
                           visibility: visibility, shared_to_feed: shareToFeed, duration_s: duration))
            .select("memory_id")
            .single()
            .execute()
            .value

        // Re-read through the RPC so the decorated row (asset name etc.) is exact.
        let fresh = await load(asset: assetId)
        if let mine = fresh.first(where: { $0.id == created.memory_id }) {
            if shareToFeed { feed.insert(mine, at: 0) }
            byUser[me, default: []].insert(mine, at: 0)
            Task { await ProgressStore.shared.award(kind: "explore", amount: 5) }
            return mine
        }
        throw NSError(domain: "Memories", code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "Saved, but couldn't load the memory yet."])
    }

    func toggleLike(_ memory: AssetMemory) async {
        guard let me else { return }
        let nowLiked = !memory.likedByMe
        mutate(memory.id) {
            $0.likedByMe = nowLiked
            $0.likeCount = max(0, $0.likeCount + (nowLiked ? 1 : -1))
        }
        do {
            if nowLiked {
                struct Like: Encodable { let memory_id: UUID; let user_id: UUID }
                try await client.from("memory_likes")
                    .upsert(Like(memory_id: memory.id, user_id: me), ignoreDuplicates: true)
                    .execute()
            } else {
                try await client.from("memory_likes").delete()
                    .eq("memory_id", value: memory.id).eq("user_id", value: me)
                    .execute()
            }
        } catch {
            mutate(memory.id) {
                $0.likedByMe = !nowLiked
                $0.likeCount = max(0, $0.likeCount + (nowLiked ? -1 : 1))
            }
        }
    }

    func markSeen(_ memory: AssetMemory) async {
        guard let me, !memory.seenByMe else { return }
        mutate(memory.id) { $0.seenByMe = true }
        struct View: Encodable { let memory_id: UUID; let user_id: UUID }
        _ = try? await client.from("memory_views")
            .upsert(View(memory_id: memory.id, user_id: me), ignoreDuplicates: true)
            .execute()
    }

    func delete(_ memory: AssetMemory) async -> Bool {
        do {
            try await client.from("asset_memories").delete()
                .eq("memory_id", value: memory.id).execute()
            feed.removeAll { $0.id == memory.id }
            for key in byAsset.keys { byAsset[key]?.removeAll { $0.id == memory.id } }
            for key in byUser.keys { byUser[key]?.removeAll { $0.id == memory.id } }
            return true
        } catch {
            return false
        }
    }

    private func mutate(_ id: UUID, _ change: (inout AssetMemory) -> Void) {
        if let i = feed.firstIndex(where: { $0.id == id }) { change(&feed[i]) }
        for key in byAsset.keys {
            if let i = byAsset[key]?.firstIndex(where: { $0.id == id }) { change(&byAsset[key]![i]) }
        }
        for key in byUser.keys {
            if let i = byUser[key]?.firstIndex(where: { $0.id == id }) { change(&byUser[key]![i]) }
        }
    }

    /// First frame of an MP4 as a poster image.
    nonisolated static func posterFrame(for mp4: Data) async -> UIImage? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard (try? mp4.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)
        guard let cg = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: cg)
    }
}
