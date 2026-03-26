//
//  Activities.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//


import Foundation
import CoreLocation


struct Activity: Identifiable, Codable {
    let id: UUID
    let placeID: UUID?
    let loopID: UUID
    let postedBy: UUID
    let name: String
    let description: String?
    let categoryId: UUID?
    let activityDateTime: Date?
    let activityImageUrl: String?
    let isUserHidden: Bool
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "activity_id"
        case placeID = "place_id"
        case loopID = "loop_id"
        case postedBy = "posted_by"
        case name
        case description
        case categoryId = "category_id"
        case activityDateTime = "activity_datetime"
        case activityImageUrl = "activity_image_url"
        case isUserHidden = "is_user_hidden"
        case createdAt = "created_at"
    }
}
