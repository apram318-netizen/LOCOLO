//
//  InboxStore.swift
//  Locolo
//
//  App-wide live view of the user's conversations: powers the redesigned
//  Messages inbox and the unread badge on the Explore header. Unread = the
//  thread changed after we last had it open. The chat screen marks threads
//  read while open, so our own sends never count. Read state stays local —
//  nothing about reading is sent to the peer.
//

import Foundation
import Combine

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var hasLoaded = false
    @Published private var lastRead: [String: Double] = [:]

    private let repo = ChatRepository()
    private var listener: Task<Void, Never>?
    private(set) var me: String?
    private let readKey = "ar.inbox.lastRead"

    private init() {
        lastRead = UserDefaults.standard.dictionary(forKey: readKey) as? [String: Double] ?? [:]
    }

    func start(userId: String) {
        let id = userId.lowercased()
        guard me != id || listener == nil else { return }
        stop()
        me = id
        listener = Task { [weak self] in
            guard let self else { return }
            for await list in self.repo.listenConversations(for: id) {
                self.seedReadState(for: list)
                self.conversations = list
                self.hasLoaded = true
                if let open = self.openConversationId { self.markRead(open) }
                await CreatorCache.shared.load(list.compactMap { self.peerId(of: $0) })
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        me = nil
        conversations = []
        hasLoaded = false
        openConversationId = nil
    }

    // MARK: Derived

    func peerId(of conversation: Conversation) -> UUID? {
        guard let me else { return nil }
        return conversation.participants
            .first { $0.lowercased() != me }
            .flatMap(UUID.init(uuidString:))
    }

    func peer(of conversation: Conversation) -> ARCreator? {
        peerId(of: conversation).flatMap { CreatorCache.shared.creator($0) }
    }

    func conversation(id: String) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Conversations with blocked people are hidden from the inbox.
    var visibleConversations: [Conversation] {
        let blocked = SafetyService.shared.blockedUserIds
        guard !blocked.isEmpty else { return conversations }
        return conversations.filter { c in
            guard let peer = peerId(of: c) else { return true }
            return !blocked.contains(peer)
        }
    }

    func isUnread(_ c: Conversation) -> Bool {
        guard me != nil, let id = c.id, id != openConversationId,
              !c.lastMessage.isEmpty else { return false }
        return c.updatedAt.timeIntervalSince1970 > (lastRead[id] ?? 0) + 0.5
    }

    /// Threads seen for the first time on this device start as read, so a
    /// fresh install doesn't light up every old conversation.
    private func seedReadState(for list: [Conversation]) {
        var changed = false
        for c in list {
            guard let id = c.id, lastRead[id] == nil else { continue }
            lastRead[id] = hasLoaded ? 0 : c.updatedAt.timeIntervalSince1970
            changed = true
        }
        if changed { UserDefaults.standard.set(lastRead, forKey: readKey) }
    }

    var unreadCount: Int {
        visibleConversations.filter(isUnread).count
    }

    // MARK: Mutations

    /// The thread currently on screen; its updates are read as they arrive.
    @Published private(set) var openConversationId: String?

    func didOpen(_ conversationId: String) {
        openConversationId = conversationId
        markRead(conversationId)
    }

    func didClose(_ conversationId: String) {
        markRead(conversationId)
        if openConversationId == conversationId { openConversationId = nil }
    }

    func markRead(_ conversationId: String) {
        let stamp = max(Date().timeIntervalSince1970,
                        conversation(id: conversationId)?.updatedAt.timeIntervalSince1970 ?? 0)
        lastRead[conversationId] = stamp
        UserDefaults.standard.set(lastRead, forKey: readKey)
    }

    func delete(_ c: Conversation) async {
        guard let id = c.id, let me else { return }
        conversations.removeAll { $0.id == id }
        do {
            try await repo.deleteConversation(conversationId: id, forUser: me)
        } catch {
            print("Delete conversation failed:", error.localizedDescription)
        }
    }

    /// Opens (restoring if soft-deleted) or creates a 1:1 thread with `userId`.
    func conversationId(with userId: UUID) async -> String? {
        guard let me else { return nil }
        let peer = userId.uuidString.lowercased()
        do {
            if let existing = try await repo.findExistingConversation(between: me, and: peer) {
                try await repo.restoreConversation(conversationId: existing, forUser: me)
                return existing
            }
            return try await repo.createConversation(between: [me, peer])
        } catch {
            print("Start conversation failed:", error.localizedDescription)
            return nil
        }
    }

    func resetForSignOut() {
        stop()
        lastRead = [:]
        UserDefaults.standard.removeObject(forKey: readKey)
    }
}
