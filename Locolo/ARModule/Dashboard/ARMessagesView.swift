//
//  ARMessagesView.swift
//  Locolo
//
//  Hosts the E2E-encrypted messages inbox inside the AR shell (WS6). Reuses
//  ConversationListView, bridging its String-path navigation onto the
//  dashboard's own stack (`ARRoute.chat`) — SwiftUI doesn't support a
//  NavigationStack nested inside a pushed destination.
//

import SwiftUI

struct ARMessagesView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState

    /// ConversationListView appends conversation ids; forward each one as a
    /// dashboard route instead of keeping a separate path.
    private var chatPath: Binding<[String]> {
        Binding(
            get: { [] },
            set: { ids in
                if let id = ids.last {
                    dashboardState.path.append(.chat(conversationId: id))
                }
            }
        )
    }

    var body: some View {
        Group {
            if let user = userVM.currentUser {
                ConversationListView(
                    currentUserId: user.id.uuidString.lowercased(),
                    currentUserName: user.name ?? user.username,
                    path: chatPath
                )
                .toolbar(.visible, for: .navigationBar)
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
