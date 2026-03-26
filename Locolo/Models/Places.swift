//
//  Places.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import Foundation
import CoreLocation

struct Place: Identifiable, Codable {
    
    let id: UUID
    let loopID: UUID?
    let postedBy: UUID?
    let name: String
    let categoryId: UUID?
    let description: String?
    let placeImageUrl: String?
    let trailerMediaUrl: String?
    let createdAt: Date?
    var locationId: UUID?
    let verificationStatus: String?
    let score: Double?
    
    var location: Location?

    enum CodingKeys: String, CodingKey {
        case id = "place_id"
        case loopID = "loop_id"
        case postedBy = "posted_by"
        case name
        case categoryId = "category_id"
        case description
        case placeImageUrl = "place_image_url"
        case trailerMediaUrl = "trailer_media_url"
        case createdAt = "created_at"
        case locationId = "location_id"
        case verificationStatus = "verification_status"
        case score
        case location = "locations"
    }
}

struct PostPlace: Identifiable, Codable {
    let id: UUID
    let loopID: UUID?
    let postedBy: UUID?
    let name: String
    let categoryId: UUID?
    let description: String?
    let placeImageUrl: String?
    let trailerMediaUrl: String?
    let createdAt: Date?
    let locationId: UUID?
    let verificationStatus: String?
  

    enum CodingKeys: String, CodingKey {
        case id = "place_id"
        case loopID = "loop_id"
        case postedBy = "posted_by"
        case name
        case categoryId = "category_id"
        case description
        case placeImageUrl = "place_image_url"
        case trailerMediaUrl = "trailer_media_url"
        case createdAt = "created_at"
        case locationId = "location_id"
        case verificationStatus = "verification_status"
    }
}


