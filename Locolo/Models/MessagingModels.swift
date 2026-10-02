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
    /// Ciphertext at rest (base64 AES-GCM). E2E encrypted — the server never
    /// sees plaintext. (WS6)
    var text: String
    var time: Date
    /// Group chats: one ciphertext per member, keyed by lowercased user id,
    /// each sealed with the sender↔member pairwise key (server-blind fan-out).
    var ciphers: [String: String]? = nil

    /// Plaintext after client-side decryption. Never persisted / uploaded.
    var decryptedText: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, senderId, senderName, text, time, ciphers
    }

    /// What the UI should show: decrypted text, or a lock if we can't read it.
    var displayText: String { decryptedText ?? "🔒 Encrypted message" }
}


struct Conversation: Identifiable, Codable {
    @DocumentID var id: String?
    var participants: [String]
    var lastMessage: String
    var updatedAt: Date
    var deletedBy: [String]?  // Tracks which users have deleted this conversation
    var deletedUpTo: [String: Date]?  // Maps userId -> timestamp of when they deleted messages
    // V3 group chats
    var isGroup: Bool?
    var name: String?
    var admins: [String]?
    var createdBy: String?

    var isGroupChat: Bool { isGroup == true }
}
