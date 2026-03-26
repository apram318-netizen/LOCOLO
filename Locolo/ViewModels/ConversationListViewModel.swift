//
//  ConversationListViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//


import Foundation

// An important think I worked on, the view model will always refer to your old chat if you have deleted it and show you no messages in there, the other user will still be able to see old messages and the new messages. Just the way I wanted.
// Description: Manages the user’s active chat list — handles live updates,
// creating new conversations, deleting old ones, and restoring soft-deleted threads.
@MainActor
final class ConversationListViewModel: ObservableObject {
    // MARK: - Published State
    @Published var conversations: [Conversation] = []   // all current conversations

    private let repo: ChatRepository                    // Firestore repo
    private let userId: String                          // normalized lowercase user ID
    private var listenerTask: Task<Void, Never>?        // async listener for conversation changes
    
    
    

    // MARK: Init
    /// - Description: Initializes and immediately starts listening to conversation updates.
    ///
    /// - Parameters:
    ///   - userId: The current logged-in user’s ID
    ///   - repo: Optional injected repository (default: new ChatRepository)
    init(userId: String, repo: ChatRepository? = nil) {
        self.repo = repo ?? ChatRepository()
        self.userId = userId.lowercased() // normalize for Firestore consistency
        startListening()
    }
    
    

    // MARK: FUNCTION: startListening
    /// - Description: Starts the real-time listener for all user conversations.
    /// Keeps the UI synced automatically as messages arrive or chats are updated.
    private func startListening() {
        listenerTask = Task {
            for await newConversations in repo.listenConversations(for: userId) {
                await MainActor.run {
                    self.conversations = newConversations
                }
            }
        }
    }
    
    

    // MARK: FUNCTION: startConversation
    /// - Description: Starts (or restores) a chat with another user.
    /// Checks Firestore for existing threads before creating a new one.
    ///
    /// - Parameter userId2: The second user’s ID to chat with
    /// - Returns: The conversation ID if available or newly created
    func startConversation(with userId2: String) async -> String? {
        let normalizedUserId2 = userId2.lowercased()

        // Check for existing conversation
        do {
            if let existingConvoId = try await repo.findExistingConversation(
                between: userId,
                and: normalizedUserId2
            ) {
                try await repo.restoreConversation(conversationId: existingConvoId, forUser: userId)
                return existingConvoId
            }
        } catch {
            print(" Error checking for existing conversation:", error)
        }

        // None found -> create new
        return try? await repo.createConversation(between: [userId, normalizedUserId2])
    }
    
    
    

    // MARK: FUNCTION: makeChatViewModel
    /// - Description: Creates a chat view model for a given conversation.
    /// Used by the UI when navigating into a chat screen.
    ///
    /// So insteadof here being a general viewmodel at the moment weare using the view model for each specific chat session
    ///
    /// - Parameter id: The conversation ID
    /// - Returns: A new `ChatViewModel` tied to that chat
    func makeChatViewModel(for id: String) -> ChatViewModel {
        ChatViewModel(conversationId: id, userId: userId)
    }

    
    
    
    // MARK: FUNCTION: deleteConversation
    /// - Description: Soft-deletes a conversation for the current users
    ///
    /// If deletion fails, the conversation is restored locally.
    /// the deletion is 2 way  in this app. Like if I delete something from my phone that just deletes it on mine.
    /// So a chat is deletedon firestore when both the users delete it.
    /// This has been done in order to implement trustable chats
    ///
    /// - Parameter conversation: The conversation object to delete
    func deleteConversation(_ conversation: Conversation) async {
        guard let conversationId = conversation.id else { return }

        // Optimistic UI update
        if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations.remove(at: index)
        }

        do {
            try await repo.deleteConversation(conversationId: conversationId, forUser: userId)
        } catch {
            print(" Failed to delete conversation:", error)
            // Roll back if it didn’t actually delete
            conversations.append(conversation)
            conversations.sort { $0.updatedAt > $1.updatedAt }
        }
    }
    
    
    
}
