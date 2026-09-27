//
//  FollowRepository.swift
//  Locolo
//
//  The follow graph for the AR social layer (WS4). Adapts to the EXISTING
//  `follows` table — columns (follower_id, followee_id, status, updated_at),
//  PK (follower_id, followee_id) — rather than a new schema. A follow is a row
//  with status = 'accepted' (Locolo v1 uses a public, instant-follow model; the
//  'requested'/'blocked' states remain available for a future private-account
//  feature). Counts come from the get_follow_counts RPC.
//

import Foundation
import Supabase

final class FollowRepository {
    private let client = SupabaseManager.shared.client

    private struct FollowRow: Encodable {
        let follower_id: UUID
        let followee_id: UUID
        let status: String
    }

    private struct FollowKeyRow: Decodable {
        let follower_id: UUID
        let followee_id: UUID
    }

    private struct CountsRow: Decodable {
        let followers: Int
        let following: Int
    }

    // MARK: Mutations

    /// Follow `target` as `me`. Upsert so a re-follow (or a prior request row)
    /// resolves cleanly to 'accepted' without a duplicate-key error.
    func follow(_ target: UUID, from me: UUID) async throws {
        let row = FollowRow(follower_id: me, followee_id: target, status: "accepted")
        try await client
            .from("follows")
            .upsert(row, onConflict: "follower_id,followee_id")
            .execute()
    }

    func unfollow(_ target: UUID, from me: UUID) async throws {
        try await client
            .from("follows")
            .delete()
            .eq("follower_id", value: me)
            .eq("followee_id", value: target)
            .execute()
    }

    // MARK: Queries

    func isFollowing(_ target: UUID, from me: UUID) async throws -> Bool {
        let rows: [FollowKeyRow] = try await client
            .from("follows")
            .select("follower_id, followee_id")
            .eq("follower_id", value: me)
            .eq("followee_id", value: target)
            .eq("status", value: "accepted")
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func counts(for user: UUID) async throws -> (followers: Int, following: Int) {
        let rows: [CountsRow] = try await client
            .rpc("get_follow_counts", params: ["p_user": user.uuidString])
            .execute()
            .value
        let r = rows.first
        return (r?.followers ?? 0, r?.following ?? 0)
    }

    /// Users who follow `user`.
    func followers(of user: UUID) async throws -> [ARCreator] {
        let rows: [FollowKeyRow] = try await client
            .from("follows")
            .select("follower_id, followee_id")
            .eq("followee_id", value: user)
            .eq("status", value: "accepted")
            .execute()
            .value
        return try await creators(for: rows.map(\.follower_id))
    }

    /// Users `user` follows.
    func following(of user: UUID) async throws -> [ARCreator] {
        let rows: [FollowKeyRow] = try await client
            .from("follows")
            .select("follower_id, followee_id")
            .eq("follower_id", value: user)
            .eq("status", value: "accepted")
            .execute()
            .value
        return try await creators(for: rows.map(\.followee_id))
    }

    // MARK: Helpers

    private func creators(for ids: [UUID]) async throws -> [ARCreator] {
        guard !ids.isEmpty else { return [] }
        let rows: [ARCreator] = try await client
            .from("users")
            .select("user_id, username, name, avatar_url, verified_flags")
            .in("user_id", values: ids.map(\.uuidString))
            .execute()
            .value
        return rows
    }
}
