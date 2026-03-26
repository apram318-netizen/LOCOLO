//
//  ChatRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//


import Foundation
import FirebaseFirestore

/// Everything runs on the main actor because it’s tied closely to UI updates.
/// Uses Firestore under the hood for real-time messaging.
@MainActor
class ChatRepository {
    private let db = Firestore.firestore()

    // MARK: FUNCTION: listenMessages
    /// - Description: Listens live to messages for a given conversation.
    /// Automatically filters out anything the user deleted earlier (based on deletedUpTo timestamp).
    ///
    /// - Parameters:
    ///   - conversationId: The Firestore document ID of the conversation
    ///   - userId: The current user’s ID
    /// - Returns: An async stream of message arrays, automatically updated in real time
    func listenMessages(conversationId: String, forUser userId: String) -> AsyncStream<[Message]> {
        AsyncStream { continuation in
            let conversationRef = db.collection("conversations").document(conversationId)
            let messagesRef = conversationRef.collection("messages").order(by: "time", descending: false)
            
            var conversationListener: ListenerRegistration?
            var messagesListener: ListenerRegistration?
            var deletedUpToDate: Date?
            
            // Listen for user-specific deletion timestamp
            conversationListener = conversationRef.addSnapshotListener { snapshot, error in
                if let error = error {
                    print(" Firestore conversation listen error:", error)
                    return
                }
                
                if let data = snapshot?.data(),
                   let deletedUpTo = data["deletedUpTo"] as? [String: Timestamp] {
                    deletedUpToDate = deletedUpTo[userId.lowercased()]?.dateValue()
                }
            }
            
            // Then stream new messages live and filter them
            messagesListener = messagesRef.addSnapshotListener { snapshot, error in
                if let error = error {
                    print(" Firestore messages listen error:", error)
                    continuation.yield([])
                    return
                }
                
                guard let docs = snapshot?.documents else {
                    continuation.yield([])
                    return
                }
                
                let allMessages = docs.compactMap { try? $0.data(as: Message.self) }
                let filtered = deletedUpToDate != nil
                    ? allMessages.filter { $0.time > deletedUpToDate! }
                    : allMessages
                
                continuation.yield(filtered)
            }

            continuation.onTermination = { _ in
                conversationListener?.remove()
                messagesListener?.remove()
            }
        }
    }
    
    

    // MARK: FUNCTION: listenConversations
    /// - Description: Streams all conversations for a user in real time.
    /// Filters out any that the user has soft-deleted.
    ///
    /// - Parameter userId: The current user’s ID
    /// - Returns: A live async stream of `Conversation` arrays
    func listenConversations(for userId: String) -> AsyncStream<[Conversation]> {
        AsyncStream { continuation in
            let listener = db.collection("conversations")
                .whereField("participants", arrayContains: userId.lowercased())
                .order(by: "updatedAt", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        print(" Firestore listenConversations ERROR:", error)
                    }
                    let allConvs = snapshot?.documents.compactMap { try? $0.data(as: Conversation.self) } ?? []
                    let visibleConvs = allConvs.filter {
                        !($0.deletedBy ?? []).contains(userId.lowercased())
                    }
                    continuation.yield(visibleConvs)
                }
            continuation.onTermination = { _ in listener.remove() }
        }
    }
    
    
    

    // MARK: FUNCTION: sendMessage
    /// - Description: Sends a new message and updates the conversation metadata (last message, timestamp).
    ///
    /// - Parameters:
    ///   - conversationId: The Firestore document ID of the conversation
    ///   - message: The `Message` object to send
    /// - Throws: If Firestore write fails
    func sendMessage(conversationId: String, message: Message) async throws {
        let ref = db.collection("conversations").document(conversationId)
        try await ref.collection("messages").addDocument(data: [
            "senderId": message.senderId.lowercased(),
            "senderName": message.senderName,
            "text": message.text,
            "time": Timestamp(date: message.time)
        ])
        try await ref.setData([
            "lastMessage": message.text,
            "updatedAt": Timestamp(date: message.time),
            "deletedBy": []  // clear soft deletes when chat resumes
        ], merge: true)
    }
    
    
    

    // MARK: FUNCTION: createConversation
    /// - Description: Creates a new chat between users and returns the Firestore ID.
    ///
    /// - Parameter users: The participant user IDs (usually 2)
    /// - Returns: The conversation’s Firestore document ID
    func createConversation(between users: [String]) async throws -> String {
        let normalized = users.map { $0.lowercased() }
        let ref = try await db.collection("conversations").addDocument(data: [
            "participants": normalized,
            "lastMessage": "",
            "updatedAt": Timestamp(date: Date())
        ])
        return ref.documentID
    }
    
    
    

    // MARK: FUNCTION: deleteConversation
    /// - Description: Deletes a conversation — soft delete for one user, full delete if everyone’s gone.
    ///
    /// - Parameters:
    ///   - conversationId: The conversation Firestore ID
    ///   - userId: The user performing the delete
    /// - Throws: If Firestore read/write fails
    func deleteConversation(conversationId: String, forUser userId: String) async throws {
        let ref = db.collection("conversations").document(conversationId)
        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data(),
              let participants = data["participants"] as? [String] else { return }

        var deletedBy = (data["deletedBy"] as? [String]) ?? []
        var deletedUpTo = (data["deletedUpTo"] as? [String: Timestamp]) ?? [:]

        if !deletedBy.contains(userId.lowercased()) {
            deletedBy.append(userId.lowercased())
        }
        deletedUpTo[userId.lowercased()] = Timestamp(date: Date())

        if deletedBy.count >= participants.count {
            // everyone deleted → full delete
            let messages = try await ref.collection("messages").getDocuments()
            let batch = db.batch()
            for doc in messages.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
            try await ref.delete()
            print(" Deleted conversation \(conversationId) permanently")
        } else {
            // otherwise, soft delete
            try await ref.updateData([
                "deletedBy": deletedBy,
                "deletedUpTo": deletedUpTo
            ])
            print(" Soft deleted conversation for \(userId)")
        }
    }
    
    
    

    // MARK: FUNCTION: findExistingConversation
    /// - Description: Checks if a conversation already exists between two users.
    ///
    /// - Parameters:
    ///   - user1: The first user’s ID
    ///   - user2: The second user’s ID
    /// - Returns: Conversation ID if found, or `nil` if no match exists
    func findExistingConversation(between user1: String, and user2: String) async throws -> String? {
        let u1 = user1.lowercased()
        let u2 = user2.lowercased()

        let snapshot = try await db.collection("conversations")
            .whereField("participants", arrayContains: u1)
            .getDocuments()

        for doc in snapshot.documents {
            if let participants = doc.data()["participants"] as? [String],
               participants.contains(u2) {
                return doc.documentID
            }
        }
        return nil
    }
    
    
    

    // MARK: FUNCTION: restoreConversation
    /// - Description: Brings back a previously soft-deleted conversation for a user.
    /// Keeps the deletion timestamp so older messages still stay hidden.
    ///
    /// - Parameters:
    ///   - conversationId: The conversation Firestore document ID
    ///   - userId: The user who’s restoring the conversation
    /// - Throws: If Firestore update fails
    func restoreConversation(conversationId: String, forUser userId: String) async throws {
        let ref = db.collection("conversations").document(conversationId)
        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data() else { return }

        var deletedBy = (data["deletedBy"] as? [String]) ?? []
        deletedBy.removeAll { $0 == userId.lowercased() }

        try await ref.updateData([
            "deletedBy": deletedBy,
            "updatedAt": Timestamp(date: Date())
        ])

        print(" Restored conversation for \(userId)")
    }
    
    
    
}

// Resources for this file:
// https://firebase.google.com/docs/firestore/query-data/listen
// https://firebase.google.com/docs/firestore/data-model#subcollections
// Building Chat App Using SwiftUI & Firebase: Adding Groups ...
// https://www.youtube.com/watch?v=xp-9BddJpWg
