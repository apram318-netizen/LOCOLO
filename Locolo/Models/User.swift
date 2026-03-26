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
