
//
//  ChatNotificationRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 13/11/2025.
//
//
//
//import Foundation
//import FirebaseFirestore
//
//@MainActor
//final class ChatNotificationRepository {
//    private let db = Firestore.firestore()
//    private let collection = "notifications"
//    
//    func logMessageNotification(
//        conversationId: String,
//        message: Message,
//        recipientId: String
//    ) async throws {
//        let messageId = message.id ?? UUID().uuidString
//        let docId = "\(conversationId)_\(recipientId.lowercased())_\(messageId)"
//        let data: [String: Any] = [
//            "type": "message",
//            "conversationId": conversationId,
//            "messageId": messageId,
//            "recipientId": recipientId.lowercased(),
//            "senderId": message.senderId.lowercased(),
//            "senderName": message.senderName,
//            "title": message.senderName,
//            "body": message.text,
//            "createdAt": Timestamp(date: Date())
//        ]
//        
//        try await db.collection(collection)
//            .document(docId)
//            .setData(data, merge: true)
//    }
//}
