//
//  Loops.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//

import Foundation
import CoreLocation


struct Loop: Identifiable, Codable {
    
    let id: String?
    let name: String
    let description: String?
    let coverImageUrl: String?
    let locationName: String
    let latitude: Double
    let longitude: Double
    let memberCount: Int
    var isMember: Bool
    var isActive: Bool
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    
    //TODO(LOCOLO): Checking if it works |Status: Uncomplete
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case coverImageUrl = "cover_image_url"
        case locationName = "location_name"
        case latitude, longitude
        case memberCount = "member_count"
        case isMember = "is_member"
        case isActive = "is_active"
    }
    
    
}
