//
//  StoryStore.swift
//  Locolo
//
//  24h ephemeral stories (Phase D). Loads the rail via get_story_rail; posts
//  new stories; marks views. Degrades to an empty rail when the stories
//  migration hasn't been applied yet.
//

import Foundation
import Combine
import Supabase
import UIKit

struct StoryItem: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let assetId: UUID?
    let mediaUrl: String
    let mediaType: String
    let caption: String?
    let createdAt: Date
    let expiresAt: Date
    var viewed: Bool

    var isExpired: Bool { expiresAt <= Date() }
}

struct StoryAuthorGroup: Identifiable {
    var id: UUID { userId }
    let userId: UUID
    var stories: [StoryItem]
    var hasUnviewed: Bool { stories.contains { !$0.viewed } }
}

@MainActor
final class StoryStore: ObservableObject {
    static let shared = StoryStore()

    @Published private(set) var items: [StoryItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) {
        if self.me != me {
            items = []
            hasLoaded = false
            available = true
        }
        self.me = me
    }

    func reset() {
        me = nil
        items = []
        hasLoaded = false
        available = true
        isLoading = false
    }

    /// Authors with active stories, own ring first, then unviewed, then viewed.
    var groups: [StoryAuthorGroup] {
        var byUser: [UUID: [StoryItem]] = [:]
        for s in items where !s.isExpired {
            byUser[s.userId, default: []].append(s)
        }
        for key in byUser.keys {
            byUser[key]?.sort { $0.createdAt < $1.createdAt }
        }
        return byUser.map { StoryAuthorGroup(userId: $0.key, stories: $0.value) }
            .sorted { a, b in
                if a.userId == me { return true }
                if b.userId == me { return false }
                if a.hasUnviewed != b.hasUnviewed { return a.hasUnviewed && !b.hasUnviewed }
                let aDate = a.stories.last?.createdAt ?? .distantPast
                let bDate = b.stories.last?.createdAt ?? .distantPast
                return aDate > bDate
            }
    }

    private struct RailRow: Decodable {
        let story_id: UUID
        let user_id: UUID
        let asset_id: UUID?
        let media_url: String
        let media_type: String
        let caption: String?
        let created_at: Date
        let expires_at: Date
        let viewed: Bool
    }

    private struct InsertRow: Decodable {
        let story_id: UUID
        let user_id: UUID
        let asset_id: UUID?
        let media_url: String
        let media_type: String
        let caption: String?
        let created_at: Date
        let expires_at: Date
    }

    func refresh() async {
        guard let me, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            let rows: [RailRow] = try await client
                .rpc("get_story_rail", params: ["p_limit": 60])
                .execute()
                .value
            available = true
            items = rows.map {
                StoryItem(id: $0.story_id, userId: $0.user_id, assetId: $0.asset_id,
                          mediaUrl: $0.media_url, mediaType: $0.media_type, caption: $0.caption,
                          createdAt: $0.created_at, expiresAt: $0.expires_at, viewed: $0.viewed)
            }
            await CreatorCache.shared.load(items.map(\.userId))
        } catch {
            if EngagementStore.isMissingSchema(error) {
                available = false
                items = []
            }
        }
    }

    /// Upload JPEG bytes and create a 24h story. Optionally links an asset.
    @discardableResult
    func post(imageData: Data, caption: String?, assetId: UUID?) async throws -> StoryItem {
        try await postMedia(data: imageData, contentType: "image/jpeg",
                            mediaType: "snapshot", fileExtension: "jpg",
                            caption: caption, assetId: assetId)
    }

    /// Upload an MP4 AR clip as a 24h video story.
    @discardableResult
    func postVideo(mp4Data: Data, caption: String?, assetId: UUID?) async throws -> StoryItem {
        try await postMedia(data: mp4Data, contentType: "video/mp4",
                            mediaType: "video", fileExtension: "mp4",
                            caption: caption, assetId: assetId)
    }

    private func postMedia(data: Data, contentType: String, mediaType: String,
                           fileExtension: String, caption: String?, assetId: UUID?) async throws -> StoryItem {
        guard let me else {
            throw NSError(domain: "Stories", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in to post a story."])
        }
        let path = "stories/\(me.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension)"
        let publicURL = try await ObjStorageManager.shared.uploadFile(
            path: path, fileData: data, contentType: contentType)

        struct Insert: Encodable {
            let user_id: UUID
            let asset_id: UUID?
            let media_url: String
            let media_type: String
            let caption: String?
        }
        let captionText = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let row: InsertRow = try await client
            .from("stories")
            .insert(Insert(user_id: me, asset_id: assetId, media_url: publicURL,
                           media_type: mediaType,
                           caption: (captionText?.isEmpty == false) ? captionText : nil))
            .select("story_id, user_id, asset_id, media_url, media_type, caption, created_at, expires_at")
            .single()
            .execute()
            .value
        let mine = StoryItem(id: row.story_id, userId: row.user_id, assetId: row.asset_id,
                             mediaUrl: row.media_url, mediaType: row.media_type, caption: row.caption,
                             createdAt: row.created_at, expiresAt: row.expires_at, viewed: true)
        items.insert(mine, at: 0)
        return mine
    }

    func markViewed(_ story: StoryItem) async {
        guard !story.viewed else { return }
        if let idx = items.firstIndex(where: { $0.id == story.id }) {
            items[idx].viewed = true
        }
        _ = try? await client
            .rpc("mark_story_viewed", params: ["p_story": story.id.uuidString.lowercased()])
            .execute()
    }

    func delete(_ story: StoryItem) async {
        items.removeAll { $0.id == story.id }
        _ = try? await client.from("stories").delete()
            .eq("story_id", value: story.id)
            .execute()
    }
}
