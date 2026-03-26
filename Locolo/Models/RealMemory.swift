//
//  RealMemory.swift
//  Locolo
//
//  Created by Apramjot Singh on 7/10/2025.
//


import Foundation

struct RealMemory: Identifiable, Codable {
    let id: UUID
    let postId: UUID?
    let authorId: UUID?
    let loopId: UUID?
    let placeId: UUID?
    let mediaUrl: URL
    let caption: String?
    let createdAt: Date
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case postId = "post_id"
        case authorId = "author_id"
        case loopId = "loop_id"
        case placeId = "place_id"
        case mediaUrl = "media_url"
        case caption
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
