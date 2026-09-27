//
//  ARCreator.swift
//  Locolo
//
//  Lightweight user row for feed cards, creator chips, profiles and
//  follower/following lists across the AR module. (WS4 — moved out of
//  ARExploreViewModel so profiles and explore can share it.)
//

import Foundation

struct ARCreator: Codable, Identifiable, Hashable {
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
