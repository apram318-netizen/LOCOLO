//
//  MessagingModels.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//

import Foundation
import FirebaseFirestore

struct Message: Identifiable, Codable {
    @DocumentID var id: String?
    var senderId: String
    var senderName: String
    var text: String
    var time: Date
}


struct Conversation: Identifiable, Codable {
    @DocumentID var id: String?
    var participants: [String]
    var lastMessage: String
    var updatedAt: Date
    var deletedBy: [String]?  // Tracks which users have deleted this conversation
    var deletedUpTo: [String: Date]?  // Maps userId -> timestamp of when they deleted messages
}
