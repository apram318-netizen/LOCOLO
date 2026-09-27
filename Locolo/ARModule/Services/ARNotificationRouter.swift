//
//  ARNotificationRouter.swift
//  Locolo
//
//  The AR app's side of UNUserNotificationCenter. NotificationManager stays
//  the delegate (it owns chat quick-reply) and forwards everything else here:
//  categories for social and nearby-art alerts, tap routing through
//  DeepLinkRouter, and foreground presentation rules (no banner for the chat
//  you're reading). Also posts the app's own local notifications.
//

import Foundation
import UIKit
import UserNotifications
import Combine

@MainActor
enum ARNotificationRouter {
    nonisolated static let socialCategory = "SOCIAL"
    nonisolated static let nearbyCategory = "AR_NEARBY"
    nonisolated static let chatCategory = "CHAT_MESSAGE"
    nonisolated static let viewARAction = "VIEW_AR"
    nonisolated static let detailsAction = "DETAILS"

    static var categories: Set<UNNotificationCategory> {
        let viewAR = UNNotificationAction(identifier: viewARAction, title: "View in AR",
                                          options: [.foreground],
                                          icon: UNNotificationActionIcon(systemImageName: "arkit"))
        let details = UNNotificationAction(identifier: detailsAction, title: "Details",
                                           options: [.foreground],
                                           icon: UNNotificationActionIcon(systemImageName: "info.circle"))
        return [
            UNNotificationCategory(identifier: socialCategory, actions: [], intentIdentifiers: [],
                                   options: []),
            UNNotificationCategory(identifier: nearbyCategory, actions: [viewAR, details],
                                   intentIdentifiers: [], options: [])
        ]
    }

    // MARK: Taps

    static func handle(_ response: UNNotificationResponse) {
        let info = response.notification.request.content.userInfo
        noteIfRemote(info)
        let router = DeepLinkRouter.shared

        if response.actionIdentifier == viewARAction {
            router.pendingRoute = .viewer
            return
        }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == detailsAction else { return }

        if let urlString = info["url"] as? String, let url = URL(string: urlString),
           router.handle(url) {
            return
        }
        // Legacy chat notifications only carry the conversation id.
        if let convo = info["conversationId"] as? String, !convo.isEmpty {
            router.pendingRoute = .chat(conversationId: convo)
        }
    }

    // MARK: Foreground presentation

    static func presentationOptions(for notification: UNNotification) -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        noteIfRemote(info)
        let type = info["type"] as? String

        if let convo = info["conversationId"] as? String,
           convo == InboxStore.shared.openConversationId {
            return []
        }
        if (info["source"] as? String) == "push", type != "message" {
            Task { await ActivityStore.shared.refresh(force: true) }
        }
        return [.banner, .list, .sound]
    }

    private static func noteIfRemote(_ info: [AnyHashable: Any]) {
        if (info["source"] as? String) == "push" {
            PushRegistry.shared.noteRemotePushReceived()
        }
    }

    // MARK: Local notifications

    struct LocalContent {
        var id: String
        var title: String
        var subtitle: String?
        var body: String
        var url: URL?
        var category: String = socialCategory
        var thread: String?
        var type: String
        var extra: [String: String] = [:]
        var imageURL: URL?
        var interruption: UNNotificationInterruptionLevel = .active
        var relevance: Double = 0.5
    }

    static func post(_ c: LocalContent) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        let content = UNMutableNotificationContent()
        content.title = c.title
        if let subtitle = c.subtitle { content.subtitle = subtitle }
        content.body = c.body
        content.sound = .default
        content.categoryIdentifier = c.category
        if let thread = c.thread { content.threadIdentifier = thread }
        content.interruptionLevel = c.interruption
        content.relevanceScore = c.relevance
        var info: [String: Any] = ["type": c.type, "source": "local"]
        if let url = c.url { info["url"] = url.absoluteString }
        for (k, v) in c.extra { info[k] = v }
        content.userInfo = info
        if let imageURL = c.imageURL, let attachment = await attachment(from: imageURL, id: c.id) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: c.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Downloads a thumbnail into a temp file UNNotificationAttachment can move.
    private static func attachment(from url: URL, id: String) async -> UNNotificationAttachment? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              data.count < 5_000_000
        else { return nil }
        let mime = (response as? HTTPURLResponse)?.mimeType ?? ""
        let ext = mime.contains("png") ? "png" : mime.contains("gif") ? "gif" : "jpg"
        let safeId = id.replacingOccurrences(of: "/", with: "-")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("notif-\(safeId)-\(UUID().uuidString.prefix(6)).\(ext)")
        do {
            try data.write(to: file)
            return try UNNotificationAttachment(identifier: safeId, url: file, options: nil)
        } catch {
            return nil
        }
    }
}

// MARK: - Badge

/// App icon badge = unread activity + unread conversations, kept in step
/// with both stores (remote pushes set their own badge from the server count;
/// opening the app reconciles it).
@MainActor
final class BadgeSync {
    static let shared = BadgeSync()
    private var cancellables: Set<AnyCancellable> = []
    private var lastValue = -1

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        ActivityStore.shared.objectWillChange
            .merge(with: InboxStore.shared.objectWillChange)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)
        update()
    }

    func stop() {
        cancellables.removeAll()
        lastValue = -1
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func update() {
        let count = ActivityStore.shared.unreadCount + InboxStore.shared.unreadCount
        guard count != lastValue else { return }
        lastValue = count
        UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

// MARK: - Outgoing events

/// Events the app reports so the server can push them to the other person.
enum ARPushEvents {
    /// Called after a chat message is stored; the server sends "New message
    /// from X" (never the encrypted body) to the recipient's devices.
    static func messageSent(conversationId: String, recipient: UUID?) {
        guard let recipient else { return }
        Task {
            _ = try? await SupabaseManager.shared.client
                .rpc("notify_message", params: [
                    "p_recipient": recipient.uuidString.lowercased(),
                    "p_conversation_id": conversationId
                ])
                .execute()
        }
    }
}
