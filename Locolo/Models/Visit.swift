//
//  Visit.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//


import Foundation

struct Visit: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let placeId: UUID
    let detectedAt: Date?
    let startedAt: Date?
    let confirmedAt: Date?
    let visitConfirmed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case placeId = "place_id"
        case detectedAt = "detected_at"
        case startedAt = "started_at"
        case confirmedAt = "confirmed_at"
        case visitConfirmed = "visit_confirmed"
    }
}

struct VisitInsert: Codable {
    let userId: UUID
    let placeId: UUID
    let startedAt: String
    let visitConfirmed: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case placeId = "place_id"
        case startedAt = "started_at"
        case visitConfirmed = "visit_confirmed"
    }
}
