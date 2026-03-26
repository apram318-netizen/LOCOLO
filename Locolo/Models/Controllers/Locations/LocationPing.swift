//
//  LocationPing.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//


import Foundation

//For pings of locations that track user's activity
struct LocationPing: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let speed: Double
    let timestamp: Date
}
