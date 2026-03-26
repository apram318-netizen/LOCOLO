//
//  AppNotification.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//


import Foundation
import FirebaseFirestore

struct AppNotification: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var title: String
    var body: String
    var type: String
    var timestamp: Date
    var read: Bool? 
}
