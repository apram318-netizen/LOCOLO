//
//  DigitalAsset.swift
//  Locolo
//
//  Created by Apramjot Singh on 2/11/2025.
//


import Foundation

struct DigitalAsset: Identifiable, Codable {
    let id: UUID
    let name: String?
    let userId: UUID
    let locationId: UUID?
    let fileUrl: String
    let thumbUrl: String?
    let fileType: String
    let category: String?
    let description: String?
    let hypeCount: Int
    let viewCount: Int
    let createdAt: Date
    let panoramaUrl: String?
    let visibility: String
    let interactionType: String?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let rotationX: Double?
    let rotationY: Double?
    let rotationZ: Double?
    let scaleX: Double?
    let scaleY: Double?
    let scaleZ: Double?
    
    
    ///Offers Now
    let isForSale: Bool?
    let acceptsOffers: Bool?
    let currentValue: Double?
    let boughtPrice: Double?
        
    // Computed data for offers
    let highestOffer: Double?
    let activeOffers: Int?
    
    enum CodingKeys: String, CodingKey {
        case id = "asset_id"
        case name
        case userId = "user_id"
        case locationId = "location_id"
        case fileUrl = "file_url"
        case thumbUrl = "thumb_url"
        case fileType = "file_type"
        case category, description
        case hypeCount = "hype_count"
        case viewCount = "view_count"
        case createdAt = "created_at"
        case panoramaUrl = "panorama_url"
        case visibility, interactionType = "interaction_type"
        case locationName = "location_name"
        case latitude, longitude
        case rotationX = "rotation_x"
        case rotationY = "rotation_y"
        case rotationZ = "rotation_z"
        case scaleX = "scale_x"
        case scaleY = "scale_y"
        case scaleZ = "scale_z"
        case isForSale = "is_for_sale"
        case acceptsOffers = "accepts_offers"
        case currentValue = "current_value"
        case boughtPrice = "bought_price"
        case highestOffer = "highest_offer"
        case activeOffers = "active_offers"
    }
}
