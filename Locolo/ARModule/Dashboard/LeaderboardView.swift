//
//  LeaderboardView.swift
//  Locolo
//
//  Phase D XP leaderboard (Explorer Passport). Hides when passport SQL
//  hasn't been applied.
//

import SwiftUI

struct LeaderboardView: View {
    @ObservedObject private var store = ProgressStore.shared
    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var dashboardState: ARDashboardState

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()
            content
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refreshLeaderboard()
            if store.progress == nil { await store.refresh() }
        }
        .refreshable {
            await store.refreshLeaderboard()
            await store.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.available && store.hasLoaded {
            ARInlineEmptyState(
                icon: "trophy",
                title: "Leaderboard coming soon",
                subtitle: "XP rankings will show up here once Explorer Passport sync is live."
            )
        } else if store.leaderboard.isEmpty {
            ProgressView().tint(.purple)
        } else {
            boardList
        }
    }

    private var boardList: some View {
        List {
            if let mine = store.progress {
                Section {
                    HStack {
                        Text("You").font(.subheadline.bold())
                        Spacer()
                        Text("Lv \(mine.level) · \(mine.xp) XP · \(mine.streakDays)d")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section("Top explorers") {
                ForEach(Array(store.leaderboard.enumerated()), id: \.element.id) { index, entry in
                    LeaderboardRow(
                        rank: index + 1,
                        entry: entry,
                        isMe: entry.userId == userVM.currentUser?.id
                    ) {
                        dashboardState.path.append(.profile(userId: entry.userId))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    let isMe: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(rank <= 3 ? .purple : .secondary)
                    .frame(width: 28)
                ARAvatarView(url: entry.avatarUrl.flatMap(URL.init(string:)),
                             name: entry.displayName, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    if let handle = entry.username {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(entry.xp) XP")
                        .font(.caption.weight(.bold))
                    Text("Lv \(entry.level)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listRowBackground(isMe ? Color.purple.opacity(0.08) : Color.clear)
    }
}
