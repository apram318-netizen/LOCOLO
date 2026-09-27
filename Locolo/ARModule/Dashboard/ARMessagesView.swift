//
//  ARMessagesView.swift
//  Locolo
//
//  Hosts the E2E-encrypted messages inbox inside the AR shell (WS6). Reuses the
//  existing ConversationListView (which drives its own String-keyed chat
//  navigation) inside a dedicated NavigationStack.
//

import SwiftUI

struct ARMessagesView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @State private var path: [String] = []

    var body: some View {
        Group {
            if let user = userVM.currentUser {
                NavigationStack(path: $path) {
                    ConversationListView(
                        currentUserId: user.id.uuidString.lowercased(),
                        currentUserName: user.name ?? user.username,
                        path: $path
                    )
                }
            } else {
                ARInlineEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Sign in to message",
                    subtitle: "Your encrypted conversations will appear here."
                )
            }
        }
    }
}
