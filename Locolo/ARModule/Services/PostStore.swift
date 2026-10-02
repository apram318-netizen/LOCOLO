//
//  PostStore.swift
//  Locolo
//
//  User posts: text + own photos, optionally quoting another post or linking
//  an asset / memory ("share something cool and add your own take").
//  Server: docs/migrations/2026_v3_memories_posts_growth.sql (`user_posts`,
//  `user_post_likes`, `get_posts`). Degrades with `available = false`.
//

import Foundation
import Combine
import Supabase
import UIKit

struct PostMedia: Codable, Hashable {
    let url: String
    let type: String   // image | video
}

struct UserPost: Identifiable, Hashable, Decodable {
    let id: UUID
    let userId: UUID
    let body: String?
    let media: [PostMedia]
    let linkedPostId: UUID?
    let linkedAssetId: UUID?
    let linkedMemoryId: UUID?
    let visibility: String
    let createdAt: Date
    var likeCount: Int
    var likedByMe: Bool
    var quoteCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "post_id", userId = "user_id", body, media
        case linkedPostId = "linked_post_id", linkedAssetId = "linked_asset_id"
        case linkedMemoryId = "linked_memory_id", visibility, createdAt = "created_at"
        case likeCount = "like_count", likedByMe = "liked_by_me", quoteCount = "quote_count"
    }
}

/// What a new post links to (the "attachment" row in the composer).
enum PostLink: Hashable {
    case post(UUID)
    case asset(UUID)
    case memory(UUID)
}

@MainActor
final class PostStore: ObservableObject {
    static let shared = PostStore()

    @Published private(set) var feed: [UserPost] = []
    @Published private(set) var byUser: [UUID: [UserPost]] = [:]
    @Published private(set) var cache: [UUID: UserPost] = [:]
    @Published private(set) var available = true
    @Published private(set) var isLoading = false

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
        byUser = [:]
        cache = [:]
        available = true
        isLoading = false
    }

    private struct Params: Encodable {
        let p_scope: String
        let p_id: UUID?
        let p_limit: Int
        let p_before: Date?
    }

    private func fetch(scope: String, id: UUID?, limit: Int = 30, before: Date? = nil) async -> [UserPost]? {
        do {
            let rows: [UserPost] = try await client
                .rpc("get_posts", params: Params(p_scope: scope, p_id: id, p_limit: limit, p_before: before))
                .execute()
                .value
            available = true
            let visible = rows.filter { !SafetyService.shared.blockedUserIds.contains($0.userId) }
            for p in visible { cache[p.id] = p }
            await CreatorCache.shared.load(Array(Set(visible.map(\.userId))))
            return visible
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return nil
        }
    }

    func refreshFeed() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let rows = await fetch(scope: "feed", id: nil) { feed = rows }
    }

    @discardableResult
    func load(user: UUID) async -> [UserPost] {
        if let rows = await fetch(scope: "user", id: user, limit: 60) { byUser[user] = rows }
        return byUser[user] ?? []
    }

    func post(_ id: UUID) async -> UserPost? {
        if let cached = cache[id] { return cached }
        return await fetch(scope: "one", id: id, limit: 1)?.first
    }

    @discardableResult
    func create(body: String?, images: [UIImage], link: PostLink?, visibility: String = "public") async throws -> UserPost {
        guard let me else {
            throw NSError(domain: "Posts", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sign in to post."])
        }
        var media: [PostMedia] = []
        for image in images.prefix(4) {
            guard let jpeg = image.locoloDownscaled(maxSide: 1600).jpegData(compressionQuality: 0.8) else { continue }
            let path = "posts/\(me.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            let url = try await ObjStorageManager.shared.uploadFile(path: path, fileData: jpeg, contentType: "image/jpeg")
            media.append(PostMedia(url: url, type: "image"))
        }

        struct Insert: Encodable {
            let user_id: UUID
            let body: String?
            let media: [PostMedia]
            let linked_post_id: UUID?
            let linked_asset_id: UUID?
            let linked_memory_id: UUID?
            let visibility: String
        }
        var linkedPost: UUID?, linkedAsset: UUID?, linkedMemory: UUID?
        switch link {
        case .post(let id): linkedPost = id
        case .asset(let id): linkedAsset = id
        case .memory(let id): linkedMemory = id
        case nil: break
        }
        let text = body?.trimmingCharacters(in: .whitespacesAndNewlines)
        struct Created: Decodable { let post_id: UUID }
        let created: Created = try await client.from("user_posts")
            .insert(Insert(user_id: me, body: (text?.isEmpty == false) ? text : nil, media: media,
                           linked_post_id: linkedPost, linked_asset_id: linkedAsset,
                           linked_memory_id: linkedMemory, visibility: visibility))
            .select("post_id")
            .single()
            .execute()
            .value

        guard let fresh = await fetch(scope: "one", id: created.post_id, limit: 1)?.first else {
            throw NSError(domain: "Posts", code: -2, userInfo: [NSLocalizedDescriptionKey: "Posted, but couldn't refresh yet."])
        }
        feed.insert(fresh, at: 0)
        byUser[me, default: []].insert(fresh, at: 0)
        if let linkedPost, var quoted = cache[linkedPost] {
            quoted.quoteCount += 1
            replace(quoted)
        }
        return fresh
    }

    func toggleLike(_ post: UserPost) async {
        guard let me else { return }
        var updated = post
        updated.likedByMe.toggle()
        updated.likeCount = max(0, updated.likeCount + (updated.likedByMe ? 1 : -1))
        replace(updated)
        do {
            if updated.likedByMe {
                struct Like: Encodable { let post_id: UUID; let user_id: UUID }
                try await client.from("user_post_likes")
                    .upsert(Like(post_id: post.id, user_id: me), ignoreDuplicates: true).execute()
            } else {
                try await client.from("user_post_likes").delete()
                    .eq("post_id", value: post.id).eq("user_id", value: me).execute()
            }
        } catch {
            replace(post)
        }
    }

    func delete(_ post: UserPost) async -> Bool {
        do {
            try await client.from("user_posts").delete().eq("post_id", value: post.id).execute()
            feed.removeAll { $0.id == post.id }
            for key in byUser.keys { byUser[key]?.removeAll { $0.id == post.id } }
            cache[post.id] = nil
            return true
        } catch {
            return false
        }
    }

    private func replace(_ post: UserPost) {
        cache[post.id] = post
        if let i = feed.firstIndex(where: { $0.id == post.id }) { feed[i] = post }
        for key in byUser.keys {
            if let i = byUser[key]?.firstIndex(where: { $0.id == post.id }) { byUser[key]![i] = post }
        }
    }
}

extension UIImage {
    /// Longest side ≤ `maxSide`, preserving aspect ratio.
    func locoloDownscaled(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
