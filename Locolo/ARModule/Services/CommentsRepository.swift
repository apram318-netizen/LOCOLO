//
//  CommentsRepository.swift
//  Locolo
//
//  Comments on AR assets, backed by public.asset_comments
//  (docs/migrations/2026_ar_social.sql). RLS enforces: you can only read
//  comments on assets you can see, post as yourself, not post on creators who
//  blocked you, and delete your own comments or any on your own asset.
//

import Foundation
import Supabase

struct AssetComment: Identifiable, Codable, Hashable {
    let id: UUID
    let assetId: UUID
    let userId: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "comment_id"
        case assetId = "asset_id"
        case userId = "user_id"
        case body
        case createdAt = "created_at"
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
    private let columns = "comment_id, asset_id, user_id, body, created_at"

    private init() {}

    func fetch(assetId: UUID, limit: Int = 200) async throws -> [AssetComment] {
        do {
            return try await client
                .from("asset_comments")
                .select(columns)
                .eq("asset_id", value: assetId)
                .order("created_at", ascending: true)
                .limit(limit)
                .execute()
                .value
        } catch {
            throw Self.map(error)
        }
    }

    private struct NewComment: Encodable {
        let asset_id: UUID
        let user_id: UUID
        let body: String
    }

    func post(assetId: UUID, userId: UUID, body: String) async throws -> AssetComment {
        let trimmed = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        do {
            return try await client
                .from("asset_comments")
                .insert(NewComment(asset_id: assetId, user_id: userId, body: trimmed))
                .select(columns)
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

    private static func map(_ error: Error) -> CommentsError {
        if EngagementStore.isMissingSchema(error) { return .unavailable }
        if let pg = error as? PostgrestError, pg.code == "42501" { return .notAllowed }
        return .failed
    }
}
