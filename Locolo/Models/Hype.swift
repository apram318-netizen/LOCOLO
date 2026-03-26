//
//  Hype.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//

import Foundation
import SwiftUI

struct Hype: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let postId: UUID
    let createdAt: Date
    
    var user: Author? // optional join if you want to show who hyped
    
    enum CodingKeys: String, CodingKey {
        case id = "hype_id"
        case userId = "user_id"
        case postId = "post_id"
        case createdAt = "created_at"
        case user
    }
}
