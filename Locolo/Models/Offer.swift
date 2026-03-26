//
//  Offer.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//


import Foundation

struct Offer: Identifiable, Codable {
    let id: UUID
    let assetId: UUID
    let buyerId: UUID
    let price: Double
    let status: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "offer_id"
        case assetId = "asset_id"
        case buyerId = "buyer_id"
        case price = "amount"
        case status
        case createdAt = "created_at"
    }
}
