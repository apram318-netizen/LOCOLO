//
//  ConversationListView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//

import SwiftUI

// Helper view to display username from user ID
struct UserDisplayName: View {
    let userId: String
    @State private var displayName: String = ""
    
    var body: some View {
        Text(displayName.isEmpty ? userId.prefix(8) + "..." : displayName)
            .task {
                await fetchUsername()
            }
    }
    
    private func fetchUsername() async {
        do {
            guard let uuid = UUID(uuidString: userId) else {
                displayName = "Unknown User"
                return
            }
            
            let repo = UsersRepository()
            if let user = try await repo.getUser(by: uuid) {
                displayName = user.username
            } else {
                displayName = "Unknown User"
            }
        } catch {
            print("Failed to fetch username: \(error)")
            displayName = "Unknown User"
        }
    }
}

struct ConversationListView: View {
    @StateObject private var vm: ConversationListViewModel
        @Binding var path: [String]          //  incoming binding from FeedView
        let currentUserId: String
        let currentUserName: String

        // MARK: View State
        @State private var showSearchSheet = false
        @State private var newChatId: String?

    init(currentUserId: String, currentUserName: String, path: Binding<[String]>) {
        self._path = path
        self.currentUserId = currentUserId.lowercased()  //  ADD .lowercased()
        self.currentUserName = currentUserName
        _vm = StateObject(wrappedValue: ConversationListViewModel(userId: currentUserId.lowercased()))  //  Here too
    }


    var body: some View {
        // MARK: Content Section
        Group {
            if vm.conversations.isEmpty {
                VStack(spacing: 12) {
                    Text("No chats yet").foregroundColor(.gray)
                    Button {
                        showSearchSheet = true
                    } label: {
                        Label("Start a chat", systemImage: "plus.bubble")
                            .padding()
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(10)
                    }
                }
            } else {
                List {
                    ForEach(vm.conversations) { convo in
                        if let convoId = convo.id {
                            Button {
                                path.append(convoId)  //  navigate manually
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        // Show other participant's username
                                        UserDisplayName(userId: getOtherParticipantId(from: convo))
                                            .font(.headline)
                                        Spacer()
                                        Text(convo.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    Text(convo.lastMessage.isEmpty ? "(No messages yet)" : convo.lastMessage)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await vm.deleteConversation(convo)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Messages")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSearchSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        
        //  stable navigation destination
        .navigationDestination(for: String.self) { convoId in
            ChatView(
                vm: vm.makeChatViewModel(for: convoId),
                currentUserId: currentUserId,
                currentUserName: currentUserName
            )
        }
        
        //  sheet for new chat
        .sheet(isPresented: $showSearchSheet) {
            UserSearchSheet(
                currentUserId: currentUserId,
                currentUserName: currentUserName
            ) { selectedUser in
                Task {
                    if let convoId = await vm.startConversation(with: selectedUser.user_id) {
                        await MainActor.run {
                            newChatId = convoId
                        }
                    }
                }
            }
        }
        
        //  push programmatically when new chat is created
        .onChange(of: newChatId) { convoId in
            guard let convoId else { return }
            newChatId = nil
            showSearchSheet = false
            
            // add convo to list if missing
            if !vm.conversations.contains(where: { $0.id == convoId }) {
                vm.conversations.insert(
                    Conversation(
                        id: convoId,
                        participants: [currentUserId.lowercased()],  //  Already normalized from init, but be explicit
                        lastMessage: "",
                        updatedAt: Date()
                    ),
                    at: 0
                )
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                path.append(convoId)
            }
        }
    }
    
    // Helper function to get the other participant's ID
    private func getOtherParticipantId(from conversation: Conversation) -> String {
        let otherParticipant = conversation.participants.first { $0 != currentUserId }
        return otherParticipant ?? "Unknown"
    }
}

