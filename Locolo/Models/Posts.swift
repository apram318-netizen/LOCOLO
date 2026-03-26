//
//  Posts.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/9/2025.
//

import Foundation
import CoreLocation

struct Post: Identifiable, Codable {
    
    let id: UUID?
    let loopId: UUID
    let authorId: UUID
    
    let caption: String?
    
    let media: URL?

    var placeMedia: URL?                 // fetched from places table
    var realMemoryMedia: URL?            // BeReal-type memory
    
    let tags: [String]?
    let placeId: UUID?
    
    let visibility: String?
    let isDeleted: Bool?
    
    let createdAt: Date
    let updatedAt: Date?
    
    let author: Author?
    
    let place: Place?
    
    let eventId: UUID?
    let eventContext: String?
    
    
    
    enum CodingKeys: String, CodingKey {
        case id = "post_id"
        case loopId = "loop_id"
        case authorId = "author_id"
        case caption = "description"
        case media
        case realMemoryMedia = "real_memory_media"
        case placeMedia = "place_media"
        case tags
        case placeId = "place_id"
        case visibility
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case author = "users"
        case place = "places"
        case eventId = "event_id"
        case eventContext = "event_context"
    }
    
    struct Author: Codable {
        let username: String
        let avatarUrl: URL?
        let loopTimeCounters: [LoopTimeCounterRow]?
        
        enum CodingKeys: String, CodingKey {
            case username
            case avatarUrl = "avatar_url"
            case loopTimeCounters = "loop_time_counters"
        }
    }
}

enum PostCategory: String, CaseIterable, Codable {
    case standard = "standard"
    case standardLocation = "standard_location"
    case portalLocation = "portal_location"
    case hoverLocation = "hover_location"
    case cloudPost = "cloud_post"
}
