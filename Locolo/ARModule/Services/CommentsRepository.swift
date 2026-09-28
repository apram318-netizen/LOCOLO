//
//  CommentsRepository.swift
//  Locolo
//
//  Comments on AR assets, backed by public.asset_comments
//  (docs/migrations/2026_ar_social.sql + 2026_v2_comment_threads.sql).
//  parent_id / likes are optional — decode tolerates missing columns until §5.16.
//

import Foundation
import Supabase

struct AssetComment: Identifiable, Codable, Hashable {
    let id: UUID
    let assetId: UUID
    let userId: UUID
    let body: String
    let createdAt: Date
    var parentId: UUID?
    var likeCount: Int = 0
    var likedByMe: Bool = false
    var pinned: Bool = false
    var hiddenByCreator: Bool = false

    enum CodingKeys: String, CodingKey {
        case id = "comment_id"
        case assetId = "asset_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
        case parentId = "parent_id"
        case pinned
        case hiddenByCreator = "hidden_by_creator"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetId = try c.decode(UUID.self, forKey: .assetId)
        userId = try c.decode(UUID.self, forKey: .userId)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        hiddenByCreator = try c.decodeIfPresent(Bool.self, forKey: .hiddenByCreator) ?? false
    }
}

enum CommentsError: LocalizedError {
    case unavailable
    case notAllowed
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Comments are coming soon."
        case .notAllowed:  return "You can't comment on this creation."
        case .failed:      return "Couldn't reach Locolo. Check your connection and try again."
        }
    }
}

final class CommentsRepository {
    static let shared = CommentsRepository()
    static let maxLength = 500

    private let client = SupabaseManager.shared.client
    private let columns = "comment_id, asset_id, user_id, body, created_at, parent_id, pinned, hidden_by_creator"
    private let columnsThreads = "comment_id, asset_id, user_id, body, created_at, parent_id"
    private let columnsLegacy = "comment_id, asset_id, user_id, body, created_at"

    private(set) var threadsAvailable = true
    private(set) var likesAvailable = true
    private(set) var moderationAvailable = true

    private init() {}

    func fetch(assetId: UUID, limit: Int = 200) async throws -> [AssetComment] {
        do {
            var comments: [AssetComment] = try await client
                .from("asset_comments")
                .select(columns)
                .eq("asset_id", value: assetId)
                .order("created_at", ascending: true)
                .limit(limit)
                .execute()
                .value
            threadsAvailable = true
            moderationAvailable = true
            comments = comments.filter { !$0.hiddenByCreator }.sorted {
                ($0.pinned ? 0 : 1, $0.createdAt) < ($1.pinned ? 0 : 1, $1.createdAt)
            }
            await attachLikes(&comments)
            return comments
        } catch {
            if EngagementStore.isMissingSchema(error) {
                moderationAvailable = false
                // pinned/hidden or parent_id missing — step down.
                do {
                    var comments: [AssetComment] = try await client
                        .from("asset_comments")
                        .select(columnsThreads)
                        .eq("asset_id", value: assetId)
                        .order("created_at", ascending: true)
                        .limit(limit)
                        .execute()
                        .value
                    threadsAvailable = true
                    await attachLikes(&comments)
                    return comments
                } catch {
                    if EngagementStore.isMissingSchema(error) {
                        threadsAvailable = false
                        do {
                            let comments: [AssetComment] = try await client
                                .from("asset_comments")
                                .select(columnsLegacy)
                                .eq("asset_id", value: assetId)
                                .order("created_at", ascending: true)
                                .limit(limit)
                                .execute()
                                .value
                            return comments
                        } catch {
                            throw Self.map(error)
                        }
                    }
                    throw Self.map(error)
                }
            }
            throw Self.map(error)
        }
    }

    func setPinned(commentId: UUID, pinned: Bool) async throws {
        try await client.from("asset_comments")
            .update(["pinned": pinned], returning: .minimal)
            .eq("comment_id", value: commentId)
            .execute()
    }

    func setHiddenByCreator(commentId: UUID, hidden: Bool) async throws {
        try await client.from("asset_comments")
            .update(["hidden_by_creator": hidden], returning: .minimal)
            .eq("comment_id", value: commentId)
            .execute()
    }

    private struct NewComment: Encodable {
        let asset_id: UUID
        let user_id: UUID
        let body: String
        let parent_id: UUID?
    }

    func post(assetId: UUID, userId: UUID, body: String, parentId: UUID? = nil) async throws -> AssetComment {
        let trimmed = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        do {
            if threadsAvailable, parentId != nil {
                return try await client
                    .from("asset_comments")
                    .insert(NewComment(asset_id: assetId, user_id: userId, body: trimmed, parent_id: parentId))
                    .select(columns)
                    .single()
                    .execute()
                    .value
            }
            struct Legacy: Encodable {
                let asset_id: UUID
                let user_id: UUID
                let body: String
            }
            return try await client
                .from("asset_comments")
                .insert(Legacy(asset_id: assetId, user_id: userId, body: trimmed))
                .select(threadsAvailable ? columns : columnsLegacy)
                .single()
                .execute()
                .value
        } catch {
            throw Self.map(error)
        }
    }

    func delete(commentId: UUID) async throws {
        do {
            try await client
                .from("asset_comments")
                .delete()
                .eq("comment_id", value: commentId)
                .execute()
        } catch {
            throw Self.map(error)
        }
    }

    private struct LikeRow: Decodable {
        let comment_id: UUID
        let like_count: Int
        let liked_by_me: Bool
    }

    private struct LikeParams: Encodable { let p_comments: [String] }
    private struct ToggleLikeParams: Encodable { let p_comment: String }

    private func attachLikes(_ comments: inout [AssetComment]) async {
        guard likesAvailable, !comments.isEmpty else { return }
        do {
            let rows: [LikeRow] = try await client
                .rpc("get_comment_like_counts", params: LikeParams(
                    p_comments: comments.map { $0.id.uuidString.lowercased() }))
                .execute()
                .value
            let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.comment_id, $0) })
            for i in comments.indices {
                if let row = map[comments[i].id] {
                    comments[i].likeCount = row.like_count
                    comments[i].likedByMe = row.liked_by_me
                }
            }
        } catch {
            if EngagementStore.isMissingSchema(error) { likesAvailable = false }
        }
    }

    @discardableResult
    func toggleLike(commentId: UUID) async throws -> Bool {
        do {
            let nowOn: Bool = try await client
                .rpc("toggle_comment_like", params: ToggleLikeParams(
                    p_comment: commentId.uuidString.lowercased()))
                .execute()
                .value
            likesAvailable = true
            return nowOn
        } catch {
            if EngagementStore.isMissingSchema(error) { likesAvailable = false }
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> CommentsError {
        if EngagementStore.isMissingSchema(error) { return .unavailable }
        if let pg = error as? PostgrestError, pg.code == "42501" { return .notAllowed }
        return .failed
    }
}
