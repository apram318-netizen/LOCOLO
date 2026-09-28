//
//  ProgressStore.swift
//  Locolo
//
//  Phase D server-backed Explorer Passport progress (XP / streak / level) and
//  XP leaderboard. Degrades when the passport migration isn't applied; the
//  client-only ExplorerPassport card still works from local activity.
//

import Foundation
import Combine
import Supabase

struct UserProgress: Equatable {
    var xp: Int
    var level: Int
    var streakDays: Int
    var discoveries: Int
    var createdCount: Int
    var lastActive: Date?
}

struct LeaderboardEntry: Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    let xp: Int
    let level: Int
    let streakDays: Int
    let username: String?
    let name: String?
    let avatarUrl: String?

    var displayName: String { name?.isEmpty == false ? name! : (username ?? "Explorer") }
}

struct WeekQuest: Identifiable, Hashable {
    var id: UUID { questId }
    let questId: UUID
    let slug: String
    let title: String
    let detail: String
    let kind: String
    let goal: Int
    let xpReward: Int
    var progress: Int
    var completed: Bool

    var fraction: Double { goal > 0 ? min(1, Double(progress) / Double(goal)) : 0 }
}

@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var progress: UserProgress?
    @Published private(set) var leaderboard: [LeaderboardEntry] = []
    @Published private(set) var weekQuests: [WeekQuest] = []
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false
    @Published private(set) var questsAvailable = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?
    private var awardedDiscoveries = Set<UUID>()

    private init() {}

    func configure(me: UUID) {
        if self.me != me {
            progress = nil
            leaderboard = []
            weekQuests = []
            hasLoaded = false
            available = true
            questsAvailable = true
            awardedDiscoveries = []
        }
        self.me = me
    }

    func reset() {
        me = nil
        progress = nil
        leaderboard = []
        weekQuests = []
        hasLoaded = false
        available = true
        questsAvailable = true
        awardedDiscoveries = []
    }

    private struct ProgressRow: Decodable {
        let user_id: UUID
        let xp: Int
        let level: Int
        let streak_days: Int
        let discoveries: Int
        let created_count: Int
        let last_active: String?
    }

    private struct BoardRow: Decodable {
        let user_id: UUID
        let xp: Int
        let level: Int
        let streak_days: Int
        let username: String?
        let name: String?
        let avatar_url: String?
    }

    private struct AwardParams: Encodable {
        let p_kind: String
        let p_amount: Int?
    }

    private struct LimitParams: Encodable { let p_limit: Int }

    func refresh() async {
        guard me != nil else { return }
        do {
            let row: ProgressRow = try await client
                .rpc("get_my_progress")
                .execute()
                .value
            available = true
            progress = Self.map(row)
        } catch {
            // Empty result (no row yet) arrives as decode error sometimes —
            // try award daily_open to ensure a row, else mark unavailable.
            if EngagementStore.isMissingSchema(error) {
                available = false
            } else {
                _ = await award(kind: "daily_open")
            }
        }
        hasLoaded = true
        await refreshQuests()
    }

    @discardableResult
    func award(kind: String, amount: Int? = nil) async -> UserProgress? {
        guard me != nil, available || !hasLoaded else { return progress }
        do {
            let row: ProgressRow = try await client
                .rpc("award_progress", params: AwardParams(p_kind: kind, p_amount: amount))
                .execute()
                .value
            available = true
            let mapped = Self.map(row)
            progress = mapped
            return mapped
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
            return progress
        }
    }

    /// First-time AR find for this asset on this device → discover XP.
    func noteDiscovery(_ assetId: UUID) {
        guard !awardedDiscoveries.contains(assetId) else { return }
        awardedDiscoveries.insert(assetId)
        Task {
            await award(kind: "discover")
            await bumpQuest(kind: "discover")
        }
    }

    func noteCreate() {
        Task {
            await award(kind: "create")
            await bumpQuest(kind: "create")
        }
    }

    func noteQuest(kind: String) {
        Task { await bumpQuest(kind: kind) }
    }

    private struct BumpParams: Encodable {
        let p_kind: String
        let p_delta: Int
    }

    private struct QuestRow: Decodable {
        let quest_id: UUID
        let slug: String
        let title: String
        let detail: String
        let kind: String
        let goal: Int
        let xp_reward: Int
        let progress: Int
        let completed: Bool
    }

    func bumpQuest(kind: String, delta: Int = 1) async {
        guard me != nil, questsAvailable else { return }
        do {
            try await client
                .rpc("bump_quest", params: BumpParams(p_kind: kind, p_delta: delta))
                .execute()
            await refreshQuests()
            await refresh()
        } catch {
            if EngagementStore.isMissingSchema(error) { questsAvailable = false }
        }
    }

    func refreshQuests() async {
        guard me != nil else { return }
        do {
            let rows: [QuestRow] = try await client
                .rpc("get_my_week_quests")
                .execute()
                .value
            questsAvailable = true
            weekQuests = rows.map {
                WeekQuest(questId: $0.quest_id, slug: $0.slug, title: $0.title,
                          detail: $0.detail, kind: $0.kind, goal: $0.goal,
                          xpReward: $0.xp_reward, progress: $0.progress,
                          completed: $0.completed)
            }
        } catch {
            if EngagementStore.isMissingSchema(error) {
                questsAvailable = false
                weekQuests = []
            }
        }
    }

    func refreshLeaderboard() async {
        do {
            let rows: [BoardRow] = try await client
                .rpc("get_xp_leaderboard", params: LimitParams(p_limit: 20))
                .execute()
                .value
            available = true
            leaderboard = rows.map {
                LeaderboardEntry(userId: $0.user_id, xp: $0.xp, level: $0.level,
                                 streakDays: $0.streak_days, username: $0.username,
                                 name: $0.name, avatarUrl: $0.avatar_url)
            }
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    private static func map(_ row: ProgressRow) -> UserProgress {
        var last: Date?
        if let s = row.last_active {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .gregorian)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            last = f.date(from: s)
        }
        return UserProgress(xp: row.xp, level: row.level, streakDays: row.streak_days,
                            discoveries: row.discoveries, createdCount: row.created_count,
                            lastActive: last)
    }
}
