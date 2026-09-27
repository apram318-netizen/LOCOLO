//
//  NotificationPreferences.swift
//  Locolo
//
//  Per-account notification switches. The server copy (notification_prefs)
//  gates remote pushes in send-push; the local mirror gates the app's own
//  local notifications (nearby art, fallbacks) even when launched in the
//  background without a network round-trip.
//

import Foundation
import Combine
import Supabase

struct NotificationPrefs: Codable, Equatable {
    var follows = true
    var hypes = true
    var comments = true
    var mentions = true
    var offers = true
    var messages = true
    var newPosts = true
    var milestones = true
    var nearby = true

    enum CodingKeys: String, CodingKey {
        case follows, hypes, comments, mentions, offers, messages
        case newPosts = "new_posts"
        case milestones, nearby
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        follows = try c.decodeIfPresent(Bool.self, forKey: .follows) ?? true
        hypes = try c.decodeIfPresent(Bool.self, forKey: .hypes) ?? true
        comments = try c.decodeIfPresent(Bool.self, forKey: .comments) ?? true
        mentions = try c.decodeIfPresent(Bool.self, forKey: .mentions) ?? true
        offers = try c.decodeIfPresent(Bool.self, forKey: .offers) ?? true
        messages = try c.decodeIfPresent(Bool.self, forKey: .messages) ?? true
        newPosts = try c.decodeIfPresent(Bool.self, forKey: .newPosts) ?? true
        milestones = try c.decodeIfPresent(Bool.self, forKey: .milestones) ?? true
        nearby = try c.decodeIfPresent(Bool.self, forKey: .nearby) ?? true
    }

    /// Whether an activity of this server `type` should alert the user.
    func allows(type: String) -> Bool {
        switch type {
        case "follow": return follows
        case "hype": return hypes
        case "comment": return comments
        case "mention": return mentions
        case "offer", "offer_status": return offers
        case "message": return messages
        case "new_post": return newPosts
        case "discovery", "milestone": return milestones
        case "nearby": return nearby
        default: return true
        }
    }
}

@MainActor
final class NotificationPreferences: ObservableObject {
    static let shared = NotificationPreferences()

    @Published var prefs: NotificationPrefs {
        didSet {
            guard prefs != oldValue else { return }
            persistLocally()
            scheduleSave()
        }
    }
    @Published private(set) var serverAvailable = true

    private let client = SupabaseManager.shared.client
    private let localKey = "ar.notifications.prefs"
    private var me: UUID?
    private var saveTask: Task<Void, Never>?
    private var isApplyingServer = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: localKey),
           let saved = try? JSONDecoder().decode(NotificationPrefs.self, from: data) {
            prefs = saved
        } else {
            prefs = NotificationPrefs()
        }
    }

    func load(me: UUID) async {
        self.me = me
        do {
            let rows: [NotificationPrefs] = try await client
                .from("notification_prefs")
                .select("follows, hypes, comments, mentions, offers, messages, new_posts, milestones, nearby")
                .eq("user_id", value: me)
                .limit(1)
                .execute()
                .value
            serverAvailable = true
            if let server = rows.first {
                isApplyingServer = true
                prefs = server
                isApplyingServer = false
            }
        } catch {
            serverAvailable = !EngagementStore.isMissingSchema(error)
        }
    }

    func reset() {
        saveTask?.cancel()
        me = nil
        isApplyingServer = true
        prefs = NotificationPrefs()
        isApplyingServer = false
        UserDefaults.standard.removeObject(forKey: localKey)
    }

    private func persistLocally() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: localKey)
        }
    }

    private struct PrefsRow: Encodable {
        let user_id: UUID
        let prefs: NotificationPrefs
        let updated_at: Date

        enum CodingKeys: String, CodingKey { case user_id, updated_at }

        func encode(to encoder: Encoder) throws {
            try prefs.encode(to: encoder)
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(updated_at, forKey: .updated_at)
        }
    }

    private func scheduleSave() {
        guard !isApplyingServer, let me, serverAvailable else { return }
        saveTask?.cancel()
        let row = PrefsRow(user_id: me, prefs: prefs, updated_at: Date())
        saveTask = Task { [client] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await client.from("notification_prefs")
                    .upsert(row, onConflict: "user_id")
                    .execute()
            } catch {
                print("Saving notification prefs failed:", error.localizedDescription)
            }
        }
    }

    /// Readable from any thread (background location callbacks).
    nonisolated static func localSnapshot() -> NotificationPrefs {
        guard let data = UserDefaults.standard.data(forKey: "ar.notifications.prefs"),
              let saved = try? JSONDecoder().decode(NotificationPrefs.self, from: data)
        else { return NotificationPrefs() }
        return saved
    }
}
