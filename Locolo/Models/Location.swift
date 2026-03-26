//
//  Location.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/9/2025.
//

import Foundation
import CoreLocation

struct Location: Codable, Identifiable {
    let id: UUID
    let name: String
    let address: String
    let city: String?
    let country: String?
    let googlePlaceId: String?
    let geom: String?
    let similarityScore: Double?
    let distMeters: Double?
    
    // new fields
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id = "location_id"
        case name
        case address
        case city
        case country
        case googlePlaceId = "google_place_id"
        case geom
        case similarityScore = "similarity_score"
        case distMeters = "dist_meters"
        case latitude
        case longitude
    }
}

 struct LocationInsertResponse: Decodable {
    let location_id: UUID
}
