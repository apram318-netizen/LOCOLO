//
//  InboxStore.swift
//  Locolo
//
//  App-wide live view of the user's conversations: powers the redesigned
//  Messages inbox and the unread badge on the Explore header. Unread = the
//  thread changed after we last had it open. The chat screen marks threads
//  read while open, so our own sends never count.
//
//  Read state syncs across the user's own devices through the
//  conversation_reads table (docs/migrations/2026_ar_notifications.sql);
//  nothing about reading is ever shared with the peer. Until server push is
//  live, a new message in a thread you don't have open raises a local
//  "New message from X" notification (quick reply works from it).
//

import Foundation
import Combine
import Supabase
import UserNotifications

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var hasLoaded = false
    @Published private var lastRead: [String: Double] = [:]

    private let repo = ChatRepository()
    private let client = SupabaseManager.shared.client
    private var listener: Task<Void, Never>?
    private(set) var me: String?
    private let readKey = "ar.inbox.lastRead"
    private var seenUpdatedAt: [String: Double] = [:]
    private var readsAvailable = true
    private var pendingReadUploads: [String: Double] = [:]
    private var uploadTask: Task<Void, Never>?

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
                let isFirstSnapshot = !self.hasLoaded
                self.seedReadState(for: list)
                self.conversations = list
                self.hasLoaded = true
                if let open = self.openConversationId { self.markRead(open) }
                await CreatorCache.shared.load(list.compactMap { self.peerId(of: $0) })
                if !isFirstSnapshot { await self.alertNewMessages(in: list) }
                for c in list {
                    if let cid = c.id { self.seenUpdatedAt[cid] = c.updatedAt.timeIntervalSince1970 }
                }
            }
        }
        Task { await syncReadState() }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        uploadTask?.cancel()
        uploadTask = nil
        pendingReadUploads = [:]
        seenUpdatedAt = [:]
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
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.notificationId(conversationId)])
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
        queueReadUpload(conversationId, stamp: stamp)
    }

    // MARK: Cross-device read state

    private struct ReadRow: Codable {
        let user_id: String
        let conversation_id: String
        let last_read_at: Date
    }

    /// Pulls read marks made on the user's other devices (newest wins).
    func syncReadState() async {
        guard let me, readsAvailable else { return }
        do {
            let rows: [ReadRow] = try await client
                .from("conversation_reads")
                .select("user_id, conversation_id, last_read_at")
                .eq("user_id", value: me)
                .execute()
                .value
            guard self.me == me else { return }
            var changed = false
            for row in rows {
                let t = row.last_read_at.timeIntervalSince1970
                if t > (lastRead[row.conversation_id] ?? 0) {
                    lastRead[row.conversation_id] = t
                    changed = true
                }
            }
            if changed { UserDefaults.standard.set(lastRead, forKey: readKey) }
        } catch {
            if EngagementStore.isMissingSchema(error) { readsAvailable = false }
        }
    }

    /// Batches read marks (a chat open marks read on every update) into one
    /// upsert every couple of seconds.
    private func queueReadUpload(_ conversationId: String, stamp: Double) {
        guard readsAvailable, me != nil else { return }
        pendingReadUploads[conversationId] = stamp
        guard uploadTask == nil else { return }
        uploadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.flushReadUploads()
        }
    }

    private func flushReadUploads() async {
        uploadTask = nil
        guard let me, !pendingReadUploads.isEmpty else { return }
        let rows = pendingReadUploads.map {
            ReadRow(user_id: me, conversation_id: $0.key,
                    last_read_at: Date(timeIntervalSince1970: $0.value))
        }
        pendingReadUploads = [:]
        do {
            try await client
                .from("conversation_reads")
                .upsert(rows, onConflict: "user_id,conversation_id")
                .execute()
        } catch {
            if EngagementStore.isMissingSchema(error) { readsAvailable = false }
        }
    }

    // MARK: Local message alerts (until server push is live)

    static func notificationId(_ conversationId: String) -> String { "chat-\(conversationId)" }

    private func alertNewMessages(in list: [Conversation]) async {
        guard !PushRegistry.shared.serverPushActive,
              NotificationPreferences.shared.prefs.messages else { return }
        let blocked = SafetyService.shared.blockedUserIds
        for c in list {
            guard let id = c.id, id != openConversationId, isUnread(c) else { continue }
            let updated = c.updatedAt.timeIntervalSince1970
            guard updated > (seenUpdatedAt[id] ?? 0) + 0.5 else { continue }
            let peerId = peerId(of: c)
            if let peerId, blocked.contains(peerId) { continue }
            let name = peer(of: c)?.displayName ?? "Someone"
            await ARNotificationRouter.post(.init(
                id: Self.notificationId(id),
                title: name,
                body: "🔒 New message",
                url: DeepLinkRouter.chatURL(for: id),
                category: ARNotificationRouter.chatCategory,
                thread: "chat-\(id)",
                type: "message",
                extra: ["conversationId": id, "senderName": name],
                relevance: 0.9))
        }
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
        readsAvailable = true
        UserDefaults.standard.removeObject(forKey: readKey)
    }
}
