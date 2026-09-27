//
//  ARMessagesView.swift
//  Locolo
//
//  The E2E-encrypted messages inbox inside the AR shell (WS6), built on
//  InboxStore: avatars, verified marks, relative times, unread state, search,
//  swipe to delete, and a composer that picks a person to message. Threads
//  push `ARRoute.chat` on the dashboard stack.
//

import SwiftUI

struct ARMessagesView: View {
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var creators = CreatorCache.shared
    @ObservedObject private var safety = SafetyService.shared

    @State private var query = ""
    @State private var showCompose = false
    @State private var pendingDelete: Conversation?
    @State private var isOpening = false

    private var conversations: [Conversation] {
        let list = inbox.visibleConversations
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter { c in
            guard let peer = inbox.peer(of: c) else { return false }
            return peer.displayName.lowercased().contains(q) || peer.username.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if userVM.currentUser == nil {
                ARInlineEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "Sign in to message",
                    subtitle: "Your encrypted conversations will appear here."
                )
            } else {
                list
            }
        }
        .background(ARDesign.screenBackground.ignoresSafeArea())
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCompose = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New message")
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .sheet(isPresented: $showCompose) {
            ARNewMessageSheet { person in
                Task { await openChat(with: person.id) }
            }
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { convo in
            Button("Delete", role: .destructive) {
                Task { await inbox.delete(convo) }
            }
        } message: { _ in
            Text("It's removed for you only. The other person keeps their copy.")
        }
        .overlay {
            if isOpening {
                ProgressView()
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var list: some View {
        List {
            if !inbox.hasLoaded {
                ForEach(0..<6, id: \.self) { _ in
                    ARRowSkeleton()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if conversations.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(conversations, id: \.id) { convo in
                    row(convo)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { pendingDelete = convo } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if inbox.isUnread(convo), let id = convo.id {
                                Button { inbox.markRead(id) } label: {
                                    Label("Read", systemImage: "envelope.open")
                                }
                                .tint(.purple)
                            }
                        }
                }
            }

            Label("Messages are end-to-end encrypted", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row(_ convo: Conversation) -> some View {
        let peer = inbox.peer(of: convo)
        let unread = inbox.isUnread(convo)
        return Button {
            guard let id = convo.id else { return }
            dashboardState.path.append(.chat(conversationId: id))
        } label: {
            HStack(spacing: 12) {
                ARAvatarView(url: peer?.avatarUrl, name: peer?.displayName ?? "?", size: 54)
                    .padding(2)
                    .overlay(Circle().strokeBorder(unread ? AnyShapeStyle(AppColors.purplePinkGradient)
                                                          : AnyShapeStyle(Color.clear), lineWidth: 2))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(peer?.displayName ?? "Locolo explorer")
                            .font(.subheadline.weight(unread ? .bold : .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if peer?.isVerified == true { ARVerifiedBadge(size: 12) }
                    }
                    HStack(spacing: 4) {
                        Text(preview(convo))
                            .lineLimit(1)
                        Text("· \(convo.updatedAt.shortRelative)")
                            .layoutPriority(1)
                    }
                    .font(.footnote.weight(unread ? .semibold : .regular))
                    .foregroundColor(unread ? .primary : .secondary)
                }

                Spacer(minLength: 8)

                if unread {
                    Circle()
                        .fill(AppColors.purplePinkGradient)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel("Unread")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let peerId = inbox.peerId(of: convo) {
                Button {
                    dashboardState.path.append(.profile(userId: peerId))
                } label: {
                    Label("View profile", systemImage: "person.crop.circle")
                }
            }
            Button(role: .destructive) { pendingDelete = convo } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func preview(_ convo: Conversation) -> String {
        let text = convo.lastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Say hi 👋" : text
    }

    private var emptyState: some View {
        Group {
            if query.isEmpty {
                ARInlineEmptyState(
                    icon: "paperplane",
                    title: "Your messages",
                    subtitle: "Send private, end-to-end encrypted messages to creators and friends.",
                    actionTitle: "Send a message",
                    action: { showCompose = true }
                )
            } else {
                ARInlineEmptyState(icon: "magnifyingglass", title: "No conversations match “\(query)”")
            }
        }
    }

    private func openChat(with userId: UUID) async {
        isOpening = true
        defer { isOpening = false }
        if let id = await inbox.conversationId(with: userId) {
            dashboardState.path.append(.chat(conversationId: id))
        }
    }
}

// MARK: - New message picker

/// Pick someone to message: people you follow first, then live search.
struct ARNewMessageSheet: View {
    let onSelect: (ARCreator) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var follows = FollowStore.shared
    @ObservedObject private var creators = CreatorCache.shared

    @State private var query = ""
    @State private var results: [ARCreator] = []
    @State private var isSearching = false

    private var suggested: [ARCreator] {
        let blocked = SafetyService.shared.blockedUserIds
        return follows.following
            .filter { !blocked.contains($0) }
            .compactMap { creators.creator($0) }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if suggested.isEmpty {
                        ARInlineEmptyState(icon: "person.2", title: "Find someone to message",
                                           subtitle: "Search by name or @username.")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        Section("Following") { rows(suggested) }
                    }
                } else if isSearching && results.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in ARRowSkeleton().listRowSeparator(.hidden) }
                } else if results.isEmpty {
                    ARInlineEmptyState(icon: "magnifyingglass", title: "No one found",
                                       subtitle: "Try a different name or username.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    rows(results)
                }
            }
            .listStyle(.plain)
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search people")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await CreatorCache.shared.load(Array(follows.following)) }
            .task(id: query) { await search() }
        }
        .presentationDetents([.large])
    }

    private func rows(_ people: [ARCreator]) -> some View {
        ForEach(people) { person in
            Button {
                dismiss()
                onSelect(person)
            } label: {
                HStack(spacing: 12) {
                    ARAvatarView(url: person.avatarUrl, name: person.displayName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        ARCreatorName(creator: person)
                        Text("@\(person.username)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "paperplane")
                        .foregroundStyle(AppColors.purplePinkGradient)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        isSearching = true
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        let found = await PeopleSearch.search(q)
        guard !Task.isCancelled else { return }
        results = found
        isSearching = false
    }
}
