//
//  User.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//

import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    let username: String
    let email: String
    let name: String?
    let bio: String?
    let avatarUrl: URL?
    let coverUrl: URL?
    let joinedAt: Date?
    let verifiedFlags: [String: Bool]?
    let stats: [String: Int]?
    
    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case email
        case name
        case bio
        case avatarUrl = "avatar_url"
        case coverUrl = "cover_url"
        case joinedAt = "joined_at"
        case verifiedFlags = "verified_flags"
        case stats
    }
}

extension User {
    /// Everything but `email`. Emails are private (see
    /// docs/migrations/2026_ar_safety_and_hardening.sql, which revokes the
    /// column from API roles), so profile queries must name their columns.
    static let publicColumns = "user_id, username, name, bio, avatar_url, cover_url, joined_at, verified_flags, stats"

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            username: try c.decode(String.self, forKey: .username),
            email: try c.decodeIfPresent(String.self, forKey: .email) ?? "",
            name: try c.decodeIfPresent(String.self, forKey: .name),
            bio: try c.decodeIfPresent(String.self, forKey: .bio),
            avatarUrl: try c.decodeIfPresent(URL.self, forKey: .avatarUrl),
            coverUrl: try c.decodeIfPresent(URL.self, forKey: .coverUrl),
            joinedAt: try c.decodeIfPresent(Date.self, forKey: .joinedAt),
            verifiedFlags: try c.decodeIfPresent([String: Bool].self, forKey: .verifiedFlags),
            stats: try c.decodeIfPresent([String: Int].self, forKey: .stats)
        )
    }

    /// Omits an empty email so a profile update built from a public-columns
    /// fetch can never blank out the stored address.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        if !email.isEmpty { try c.encode(email, forKey: .email) }
        try c.encode(name, forKey: .name)
        try c.encode(bio, forKey: .bio)
        try c.encode(avatarUrl, forKey: .avatarUrl)
        try c.encode(coverUrl, forKey: .coverUrl)
        try c.encode(joinedAt, forKey: .joinedAt)
        try c.encodeIfPresent(verifiedFlags, forKey: .verifiedFlags)
        try c.encode(stats, forKey: .stats)
    }
}



// One for joins-- This is solely for making fetching lighter
struct Author: Identifiable, Codable {
    let id: UUID
    let username: String
    let avatarUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case avatarUrl = "avatar_url"
    }
}
