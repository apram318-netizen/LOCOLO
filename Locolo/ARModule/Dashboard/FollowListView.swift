//
//  FollowListView.swift
//  Locolo
//
//  Followers / Following lists for a creator (WS4). Segmented switch between
//  the two; each row links to that creator's profile.
//

import SwiftUI

struct FollowListView: View {
    let userId: UUID
    @State private var showingFollowers: Bool

    @EnvironmentObject private var dashboardState: ARDashboardState
    @Environment(\.dismiss) private var dismiss

    @State private var followers: [ARCreator] = []
    @State private var following: [ARCreator] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    private let repo = FollowRepository()

    init(userId: UUID, showingFollowers: Bool) {
        self.userId = userId
        _showingFollowers = State(initialValue: showingFollowers)
    }

    private var rows: [ARCreator] { showingFollowers ? followers : following }

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            VStack(spacing: 12) {
                picker

                if isLoading {
                    ProgressView().tint(.purple).frame(maxHeight: .infinity)
                } else if loadFailed && rows.isEmpty {
                    ARInlineEmptyState(
                        icon: "wifi.exclamationmark",
                        title: "Couldn't load connections",
                        subtitle: "Check your connection and try again.",
                        actionTitle: "Retry",
                        action: { Task { await load() } }
                    )
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
                } else if rows.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(rows) { creator in
                                creatorRow(creator)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: "Connections") { EmptyView() }
                .overlay(alignment: .leading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                            .padding(9)
                            .background(Circle().fill(ARDesign.headerButtonCircle))
                    }
                    .padding(.leading, 16)
                    .accessibilityLabel("Back")
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var picker: some View {
        Picker("", selection: $showingFollowers) {
            Text("Followers").tag(true)
            Text("Following").tag(false)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private func creatorRow(_ creator: ARCreator) -> some View {
        Button {
            dashboardState.path.append(.profile(userId: creator.id))
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: creator.avatarUrl) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.2))
                        Image(systemName: "person.fill").font(.caption).foregroundColor(.purple)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(creator.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        if creator.isVerified {
                            Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue)
                        }
                    }
                    Text("@\(creator.username)").font(.caption).foregroundColor(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(12)
            .arGlassCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.largeTitle)
                .foregroundColor(.purple.opacity(0.4))
            Text(showingFollowers ? "No followers yet" : "Not following anyone yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        async let f = repo.followers(of: userId)
        async let g = repo.following(of: userId)
        let loadedFollowers = try? await f
        let loadedFollowing = try? await g
        followers = loadedFollowers ?? []
        following = loadedFollowing ?? []
        loadFailed = loadedFollowers == nil || loadedFollowing == nil
        isLoading = false
    }
}
