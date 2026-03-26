//
//  Events.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import Foundation
import CoreLocation

struct Event: Identifiable, Codable {
    let id: UUID
    let placeID: UUID?  // Made optional - can be NULL in database
    let loopID: UUID?    // Made optional - can be NULL in database
    let postedBy: UUID
    let name: String
    let description: String?
    let categoryId: UUID?
    let eventImageUrl: String?
    let trailerMediaUrl: String?
    let createdAt: Date?
    
    // MARK: EVENT POSTING FLOW - Additional fields from database schema
    let price: Double?
    let isFree: Bool?
    let maxAttendees: Int?
    let eventType: String?
    let startAt: Date?  // Replaces eventDateTime
    let endAt: Date?
    let timezone: String?
    let officialUrl: String?
    let officialUrlLabel: String?
    let locationMode: String?
    let onlineUrl: String?
    let visibility: String?
    let status: String?
    let currency: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case placeID = "place_id"
        case loopID = "loop_id"
        case postedBy = "posted_by"
        case name
        case description
        case categoryId = "category_id"
        case eventImageUrl = "event_image_url"
        case trailerMediaUrl = "trailer_media_url"
        case createdAt = "created_at"
        // EVENT POSTING FLOW - New fields
        case price
        case isFree = "is_free"
        case maxAttendees = "max_attendees"
        case eventType = "event_type"
        case startAt = "start_at"
        case endAt = "end_at"
        case timezone
        case officialUrl = "official_url"
        case officialUrlLabel = "official_url_label"
        case locationMode = "location_mode"
        case onlineUrl = "online_url"
        case visibility
        case status
        case currency
    }
    
    // Convenience initializer for backward compatibility
    init(
        id: UUID,
        placeID: UUID? = nil,
        loopID: UUID? = nil,
        postedBy: UUID,
        name: String,
        description: String? = nil,
        categoryId: UUID? = nil,
        eventImageUrl: String? = nil,
        trailerMediaUrl: String? = nil,
        createdAt: Date? = nil,
        price: Double? = nil,
        isFree: Bool? = nil,
        maxAttendees: Int? = nil,
        eventType: String? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        timezone: String? = nil,
        officialUrl: String? = nil,
        officialUrlLabel: String? = nil,
        locationMode: String? = nil,
        onlineUrl: String? = nil,
        visibility: String? = nil,
        status: String? = nil,
        currency: String? = nil
    ) {
        self.id = id
        self.placeID = placeID
        self.loopID = loopID
        self.postedBy = postedBy
        self.name = name
        self.description = description
        self.categoryId = categoryId
        self.eventImageUrl = eventImageUrl
        self.trailerMediaUrl = trailerMediaUrl
        self.createdAt = createdAt
        self.price = price
        self.isFree = isFree
        self.maxAttendees = maxAttendees
        self.eventType = eventType
        self.startAt = startAt
        self.endAt = endAt
        self.timezone = timezone
        self.officialUrl = officialUrl
        self.officialUrlLabel = officialUrlLabel
        self.locationMode = locationMode
        self.onlineUrl = onlineUrl
        self.visibility = visibility
        self.status = status
        self.currency = currency
    }
}

// MARK: EVENT POSTING FLOW - Hashable conformance for SwiftUI Picker
extension Event: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Event, rhs: Event) -> Bool {
        lhs.id == rhs.id
    }
}


// Now I need to monitor the attendees of the event, For that I need to either add a list of it in the firestore with the event Id, or I can do it realationally in the supabase by adding a table for attendees 

// ... existing Event struct and extensions ...

// MARK: ========================================
// MARK: EVENT POSTING FLOW - ADDED RECENTLY
// MARK: ========================================
// PostEvent struct for creating new events (similar to PostPlace pattern)
struct PostEvent: Identifiable, Codable {
    let id: UUID
    let placeID: UUID?
    let loopID: UUID?  // Made optional to prevent random UUID generation
    let postedBy: UUID
    let name: String
    let description: String?
    let categoryId: UUID?
    let eventImageUrl: String?
    let trailerMediaUrl: String?
    let createdAt: Date?
    
    // Required fields from database schema
    let startAt: Date
    let endAt: Date
    
    // Optional fields
    let price: Double?
    let isFree: Bool?
    let maxAttendees: Int?
    let eventType: String?
    let timezone: String?
    let officialUrl: String?
    let officialUrlLabel: String?
    let locationMode: String?
    let onlineUrl: String?
    let visibility: String?
    let status: String?
    let currency: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "event_id"
        case placeID = "place_id"
        case loopID = "loop_id"
        case postedBy = "posted_by"
        case name
        case description
        case categoryId = "category_id"
        case eventImageUrl = "event_image_url"
        case trailerMediaUrl = "trailer_media_url"
        case createdAt = "created_at"
        case startAt = "start_at"
        case endAt = "end_at"
        case price
        case isFree = "is_free"
        case maxAttendees = "max_attendees"
        case eventType = "event_type"
        case timezone
        case officialUrl = "official_url"
        case officialUrlLabel = "official_url_label"
        case locationMode = "location_mode"
        case onlineUrl = "online_url"
        case visibility
        case status
        case currency
    }
}
