//
//  Echo.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//


import Foundation

struct Echo: Identifiable, Codable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let parentEchoId: UUID?
    let content: String
    let createdAt: Date
    let updatedAt: Date?
    let isDeleted: Bool
    
    var author: Author?
    
    enum CodingKeys: String, CodingKey {
        case id = "echo_id"
        case postId = "post_id"
        case userId = "user_id"
        case parentEchoId = "parent_echo_id"
        case content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isDeleted = "is_deleted"
        case author
    }
}
