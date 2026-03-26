//
//  ChatViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//

import Foundation

/// Handles listening to Firestore message streams and sending new messages in real-time.
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [Message] = []       // all messages in current conversation

    private let repo = ChatRepository()
    private var conversationId: String            // Firestore document ID for the chat
    private var userId: String
    private var listenerTask: Task<Void, Never>?  // async listener for message updates

    // MARK: Init
    /// - Description: Sets up a new chat view model for a given conversation and user.
    /// Starts listening to messages immediately.
    ///
    /// - Parameters:
    ///   - conversationId: The Firestore conversation document ID
    ///   - userId: The ID of the user currently in the chat
    init(conversationId: String, userId: String) {
        self.conversationId = conversationId
        self.userId = userId
        startListening()
    }
    

    // MARK: FUNCTION: startListening
    /// - Description: Begins streaming messages from Firestore in real-time.
    /// Automatically updates the `messages` array whenever new data comes in.
    private func startListening() {
        listenerTask = Task {
            do {
                for await newMessages in repo.listenMessages(conversationId: conversationId, forUser: userId) {
                    await MainActor.run {
                        let oldCount = self.messages.count
                        self.messages = newMessages

                        // Show notification if new message from other user
                        if let last = newMessages.last, last.senderId != self.userId,
                           last.id != self.getLastNotifiedId() {
                            
                            // store so it NEVER fires again for this message
                            self.setLastNotifiedId(last.id)
                            
                            // show local notification
                            NotificationManager.shared
                                .showInAppNotification(for: last, conversationId: self.conversationId)
                        }
                    }
                }
            } catch {
                print("ChatViewModel listener error:", error)
            }
        }
    }
    

    // MARK: FUNCTION: sendMessage
    /// - Description: Sends a new message in the current conversation.
    /// Wraps Firestore calls in a background Task to avoid blocking the UI.
    ///
    /// - Parameters:
    ///   - text: The message body
    ///   - senderId: The UUID/string ID of the sender
    ///   - senderName: Display name of the sender
    func sendMessage(_ text: String, senderId: String, senderName: String) {
        Task {
            let msg = Message(
                senderId: senderId.lowercased(),
                senderName: senderName,
                text: text,
                time: Date()
            )
            try? await repo.sendMessage(conversationId: conversationId, message: msg)
        }
    }
    
    
    private func getLastNotifiedId() -> String? {
        UserDefaults.standard.string(forKey: "lastNotified_\(conversationId)")
    }

    private func setLastNotifiedId(_ id: String?) {
        UserDefaults.standard.set(id, forKey: "lastNotified_\(conversationId)")
    }
    
}
