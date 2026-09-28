//
//  ExplorerPassport.swift
//  Locolo
//
//  A light game layer over what the user already does: finding assets in
//  the AR viewer (DiscoveryStore), exploring them (asset_views), creating,
//  and earning hype. Everything is derived client-side — no schema needed.
//

import SwiftUI

struct ExplorerPassport {
    struct Level {
        let number: Int
        let title: String
        let floorXP: Int
        let nextXP: Int?

        var icon: String {
            ["figure.walk", "binoculars.fill", "map.fill", "safari.fill", "globe.europe.africa.fill", "crown.fill"][min(number - 1, 5)]
        }
    }

    struct Badge: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let progress: Int
        let goal: Int

        var earned: Bool { progress >= goal }
        var fraction: Double { min(1, Double(progress) / Double(goal)) }
    }

    let discoveries: Int
    let explored: Int
    let created: Int
    let hypeReceived: Int
    let streakDays: Int

    static let xpPerDiscovery = 50
    static let xpPerCreation = 100
    static let xpPerExplore = 10
    static let xpPerHype = 5

    private static let levels: [(title: String, xp: Int)] = [
        ("Wanderer", 0), ("Scout", 250), ("Pathfinder", 750),
        ("Explorer", 1_500), ("Cartographer", 3_000), ("Legend", 6_000)
    ]

    var xp: Int {
        discoveries * Self.xpPerDiscovery + created * Self.xpPerCreation
            + explored * Self.xpPerExplore + hypeReceived * Self.xpPerHype
    }

    var level: Level {
        let index = Self.levels.lastIndex { xp >= $0.xp } ?? 0
        let next = index + 1 < Self.levels.count ? Self.levels[index + 1].xp : nil
        return Level(number: index + 1, title: Self.levels[index].title,
                     floorXP: Self.levels[index].xp, nextXP: next)
    }

    /// 0…1 progress through the current level.
    var levelProgress: Double {
        guard let next = level.nextXP else { return 1 }
        return Double(xp - level.floorXP) / Double(next - level.floorXP)
    }

    var badges: [Badge] {
        [
            Badge(id: "first-find", title: "First Find", detail: "Walk up to an asset in AR",
                  icon: "sparkle.magnifyingglass", progress: discoveries, goal: 1),
            Badge(id: "scout", title: "Scout", detail: "Find 5 assets in AR",
                  icon: "binoculars.fill", progress: discoveries, goal: 5),
            Badge(id: "cartographer", title: "Cartographer", detail: "Find 25 assets in AR",
                  icon: "map.fill", progress: discoveries, goal: 25),
            Badge(id: "curious", title: "Curious", detail: "Explore 10 creators' assets",
                  icon: "eye.fill", progress: explored, goal: 10),
            Badge(id: "maker", title: "Maker", detail: "Publish your first asset",
                  icon: "cube.transparent.fill", progress: created, goal: 1),
            Badge(id: "prolific", title: "Prolific", detail: "Publish 10 assets",
                  icon: "square.stack.3d.up.fill", progress: created, goal: 10),
            Badge(id: "hype-magnet", title: "Hype Magnet", detail: "Earn 50 hype",
                  icon: "bolt.fill", progress: hypeReceived, goal: 50),
            Badge(id: "on-fire", title: "On Fire", detail: "3-day activity streak",
                  icon: "flame.fill", progress: streakDays, goal: 3),
            Badge(id: "week-warrior", title: "Week Warrior", detail: "7-day activity streak",
                  icon: "calendar.badge.checkmark", progress: streakDays, goal: 7)
        ]
    }

    /// - Parameter activity: every date the user did something (found,
    ///   explored, or created an asset).
    static func build(discoveries: Int, explored: Int, ownAssets: [DigitalAsset],
                      activity: [Date], now: Date = Date()) -> ExplorerPassport {
        ExplorerPassport(
            discoveries: discoveries,
            explored: explored,
            created: ownAssets.count,
            hypeReceived: ownAssets.reduce(0) { $0 + $1.hypeCount },
            streakDays: streak(from: activity + ownAssets.map(\.createdAt), now: now)
        )
    }

    /// Consecutive active days ending today — or yesterday, so a streak
    /// isn't "broken" first thing in the morning.
    static func streak(from dates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

// MARK: - Card

struct ExplorerPassportCard: View {
    let passport: ExplorerPassport
    @ObservedObject private var progress = ProgressStore.shared
    @State private var selectedBadge: ExplorerPassport.Badge?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                levelRing
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPLORER PASSPORT")
                        .font(.caption2.weight(.heavy))
                        .kerning(1.2)
                        .foregroundColor(.secondary)
                    Text("Level \(passport.level.number) · \(passport.level.title)")
                        .font(.headline)
                    if let next = passport.level.nextXP {
                        Text("\(next - passport.xp) XP to next level")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Max level — legendary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let server = progress.progress {
                        Text("Synced · \(server.xp) XP · \(server.streakDays)d streak")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
                Spacer(minLength: 0)
                streakPill
            }

            HStack(spacing: 0) {
                stat(passport.discoveries, "Found", icon: "sparkle.magnifyingglass")
                stat(passport.explored, "Explored", icon: "eye")
                stat(passport.created, "Created", icon: "cube.transparent")
                stat(passport.hypeReceived, "Hype", icon: "bolt")
            }

            if progress.questsAvailable && !progress.weekQuests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This week")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.secondary)
                    ForEach(progress.weekQuests.prefix(3)) { quest in
                        HStack(spacing: 10) {
                            Image(systemName: quest.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(quest.completed ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quest.title)
                                    .font(.caption.weight(.semibold))
                                Text("\(min(quest.progress, quest.goal))/\(quest.goal) · +\(quest.xpReward) XP")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            ProgressView(value: quest.fraction)
                                .tint(.purple)
                                .frame(width: 48)
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sortedBadges) { badge in
                        Button { selectedBadge = badge } label: { badgeView(badge) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if let badge = selectedBadge {
                HStack(spacing: 8) {
                    Image(systemName: badge.earned ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundColor(badge.earned ? .green : .secondary)
                    Text("\(badge.title): \(badge.detail)")
                        .font(.caption)
                    Spacer(minLength: 0)
                    Text(badge.earned ? "Earned" : "\(badge.progress)/\(badge.goal)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .arGlassCard(cornerRadius: 22)
        .animation(.easeInOut(duration: 0.2), value: selectedBadge?.id)
        .task {
            if progress.weekQuests.isEmpty { await progress.refreshQuests() }
        }
    }

    /// Earned first, then closest to earning.
    private var sortedBadges: [ExplorerPassport.Badge] {
        passport.badges.sorted {
            if $0.earned != $1.earned { return $0.earned }
            return $0.fraction > $1.fraction
        }
    }

    private var levelRing: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: passport.levelProgress)
                .stroke(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: passport.level.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(passport.level.number), \(Int(passport.levelProgress * 100)) percent to next level")
    }

    private var streakPill: some View {
        VStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(passport.streakDays > 0
                                 ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                                 : AnyShapeStyle(Color.secondary.opacity(0.5)))
            Text("\(passport.streakDays)d")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(passport.streakDays) day streak")
    }

    private func stat(_ value: Int, _ label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.purple)
            Text("\(value)")
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func badgeView(_ badge: ExplorerPassport.Badge) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.earned
                          ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.primary.opacity(0.06)))
                if !badge.earned {
                    Circle()
                        .trim(from: 0, to: badge.fraction)
                        .stroke(Color.purple.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: badge.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badge.earned ? .white : .secondary)
            }
            .frame(width: 50, height: 50)
            Text(badge.title)
                .font(.caption2.weight(.medium))
                .foregroundColor(badge.earned ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: 70)
        .opacity(badge.earned ? 1 : 0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title) badge, \(badge.earned ? "earned" : "\(badge.progress) of \(badge.goal)")")
    }
}
