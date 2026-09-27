//
//  ARChatScreen.swift
//  Locolo
//
//  Owns a ChatViewModel for the lifetime of the screen. ChatView observes
//  (doesn't own) its view model, so building `ChatViewModel(...)` inline in
//  a navigation destination or sheet re-created it — and its Firestore
//  listener — on every parent re-render.
//

import SwiftUI

struct ARChatScreen: View {
    let conversationId: String
    let title: String
    let currentUserId: String
    let currentUserName: String

    @StateObject private var vm: ChatViewModel
    @ObservedObject private var inbox = InboxStore.shared

    init(conversationId: String, peerId: UUID? = nil, title: String = "Chat",
         currentUserId: String, currentUserName: String) {
        self.conversationId = conversationId
        self.title = title
        self.currentUserId = currentUserId.lowercased()
        self.currentUserName = currentUserName
        _vm = StateObject(wrappedValue: ChatViewModel(
            conversationId: conversationId,
            userId: currentUserId.lowercased(),
            peerId: peerId
        ))
    }

    var body: some View {
        ChatView(vm: vm, currentUserId: currentUserId, currentUserName: currentUserName)
            .navigationTitle(resolvedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .onAppear { inbox.didOpen(conversationId) }
            .onDisappear { inbox.didClose(conversationId) }
    }

    /// Falls back to the peer's name from the inbox when pushed by id only.
    private var resolvedTitle: String {
        guard title == "Chat",
              let convo = inbox.conversation(id: conversationId),
              let peer = inbox.peer(of: convo) else { return title }
        return peer.displayName
    }
}
