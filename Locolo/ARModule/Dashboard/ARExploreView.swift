//
//  ARExploreView.swift
//  Locolo
//
//  The Explore tab: featured carousel plus the AR social feed with
//  For You / Trending / Nearby filters and infinite scrolling.
//  Replaces the old ARWorldHomeView.
//

import SwiftUI

struct ARExploreView: View {
    var onDismiss: (() -> Void)? = nil

    @StateObject private var vm = ARExploreViewModel()
    @EnvironmentObject private var dashboardState: ARDashboardState
    @ObservedObject private var inbox = InboxStore.shared
    @ObservedObject private var activity = ActivityStore.shared
    @ObservedObject private var follows = FollowStore.shared
    @ObservedObject private var stories = StoryStore.shared
    @ObservedObject private var events = EventsStore.shared
    @ObservedObject private var presence = PresenceStore.shared

    @State private var selectedAsset: DigitalAsset?
    @State private var commentsAsset: DigitalAsset?
    @State private var featuredPage = 0
    @State private var showImmersiveFeed = false

    var body: some View {
        ZStack {
            ARDesign.screenBackground.ignoresSafeArea()

            if vm.isLoading {
                loadingView
            } else {
                ScrollView(showsIndicators: false) {
                    if let error = vm.errorMessage {
                        ARInlineEmptyState(
                            icon: "wifi.exclamationmark",
                            title: "You're offline",
                            subtitle: error,
                            actionTitle: "Retry",
                            action: { Task { await vm.refresh() } }
                        )
                        .padding(.top, 60)
                    } else {
                        VStack(spacing: 0) {
                            StoryRailView()
                            featuredSection
                            exploreRailsSection
                            suggestedCreatorsSection
                            feedSection
                        }
                        .padding(.bottom, 24)
                    }
                }
                .refreshable {
                    async let feed: Void = vm.refresh()
                    async let followsReload: Void = follows.reload()
                    async let activityReload: Void = activity.refresh()
                    async let storiesReload: Void = stories.refresh()
                    async let presenceReload: Void = presence.refreshNearby()
                    async let eventsReload: Void = events.refresh()
                    _ = await (feed, followsReload, activityReload, storiesReload, presenceReload, eventsReload)
                    await presence.heartbeat()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: "AR World", subtitle: "Shared Creative Space", onExit: onDismiss) {
                HStack(spacing: 8) {
                    ARHeaderIconButton(icon: "arkit", label: "Open AR viewer") {
                        dashboardState.path.append(.viewer)
                    }
                    ARBadgedIconButton(icon: "bell", label: "Activity", badge: activity.unreadCount) {
                        dashboardState.path.append(.activity)
                    }
                    ARBadgedIconButton(icon: "paperplane", label: "Messages", badge: inbox.unreadCount) {
                        dashboardState.path.append(.conversations)
                    }
                }
            }
        }
        .task { await vm.load() }
        .task {
            if !stories.hasLoaded { await stories.refresh() }
            await presence.heartbeat()
            await presence.refreshNearby()
        }
        .task(id: vm.visibleFeed.map(\.id)) {
            await EngagementStore.shared.prime(vm.visibleFeed)
            await RepostStore.shared.prime(vm.visibleFeed)
            await ReactionStore.shared.prime(vm.visibleFeed)
        }
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(
                asset: asset,
                onOpenCreator: { dashboardState.path.append(.profile(userId: asset.userId)) },
                onOpenProfile: { openProfile($0) },
                onRemix: {
                    selectedAsset = nil
                    dashboardState.path.append(.create)
                }
            )
        }
        .sheet(item: $commentsAsset) { asset in
            CommentsSheet(asset: asset, onOpenProfile: { openProfile($0) })
        }
        .fullScreenCover(isPresented: $showImmersiveFeed) {
            ImmersiveFeedView(
                assets: vm.feedAssets,
                creatorFor: { vm.creator(for: $0) },
                isTrending: { vm.isTrending($0) },
                onClose: { showImmersiveFeed = false },
                onOpenCreator: { openProfile($0) },
                onOpenInAR: {
                    showImmersiveFeed = false
                    dashboardState.path.append(.viewer)
                },
                onNearEnd: { vm.loadMoreIfNeeded(current: $0) }
            )
            .task(id: vm.visibleFeed.map(\.id)) {
                await EngagementStore.shared.prime(vm.visibleFeed)
                await ReactionStore.shared.prime(vm.visibleFeed)
            }
        }
    }

    private func openProfile(_ id: UUID) {
        dashboardState.path.append(.profile(userId: id))
    }

    // MARK: - Rails (trending near you / drops / events / presence)

    @ViewBuilder
    private var exploreRailsSection: some View {
        VStack(spacing: 0) {
            if !vm.trendingNearYou.isEmpty {
                assetRail(title: "Trending near you", icon: "flame.fill", assets: vm.trendingNearYou)
            }
            if !vm.dropsToday.isEmpty {
                assetRail(title: "Drops today", icon: "sparkle", assets: vm.dropsToday)
            }
            if events.available && !events.upcoming.isEmpty {
                Button {
                    dashboardState.path.append(.events)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(AppColors.purplePinkGradient)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AR Events")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text("\(events.upcoming.count) meetup\(events.upcoming.count == 1 ? "" : "s") coming up")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.adaptive(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.06))))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
                .buttonStyle(.plain)
            }
            if presence.available && !presence.nearby.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.purple)
                    Text("\(presence.nearby.count) explorer\(presence.nearby.count == 1 ? "" : "s") nearby")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    private func assetRail(title: String, icon: String, assets: [DigitalAsset]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline.bold())
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(assets) { asset in
                        Button { selectedAsset = asset } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AssetThumbnailView(asset: asset, cornerRadius: 14)
                                    .frame(width: 112, height: 112)
                                Text(asset.name ?? "Untitled")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(width: 112, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                ARSkeletonBlock(height: 220, cornerRadius: 20)
                    .arShimmer()
                ForEach(0..<3, id: \.self) { _ in ARFeedCardSkeleton() }
            }
            .padding(16)
        }
        .scrollDisabled(true)
        .accessibilityLabel("Loading AR World")
    }

    // MARK: - Suggested creators

    @ViewBuilder
    private var suggestedCreatorsSection: some View {
        let suggestions = vm.suggestedCreators
        if follows.isLoaded && !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Creators to follow", systemImage: "person.2.fill")
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            SuggestedCreatorCard(suggestion: suggestion) {
                                openProfile(suggestion.creator.id)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .animation(ARDesign.spring, value: suggestions.map(\.id))
                }
            }
        }
    }

    // MARK: - Featured

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Famous Assets", systemImage: "star.fill")
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if vm.visibleFeatured.isEmpty {
                emptyFeaturedPlaceholder
            } else {
                featuredCarousel
            }
        }
    }

    private var featuredCarousel: some View {
        TabView(selection: $featuredPage) {
            ForEach(Array(vm.visibleFeatured.enumerated()), id: \.element.id) { index, asset in
                ARFeaturedCard(asset: asset)
                    .padding(.horizontal, 16)
                    .onTapGesture { selectedAsset = asset }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 240)
    }

    private var emptyFeaturedPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.adaptive(light: Color.black.opacity(0.05), dark: Color.white.opacity(0.05)))
            .frame(height: 200)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.purple.opacity(0.5))
                    Text("No featured assets yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            )
            .padding(.horizontal, 16)
    }

    // MARK: - Feed

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ARSectionHeader(
                    title: "Shared Space",
                    subtitle: "AR art placed around the world",
                    icon: "globe.americas.fill"
                )
                Spacer(minLength: 0)
                Button {
                    ARHaptics.tick()
                    showImmersiveFeed = true
                } label: {
                    Label("Swipe", systemImage: "rectangle.stack.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(AppColors.purplePinkGradient))
                }
                .accessibilityLabel("Open immersive For You feed")
                .padding(.top, 24)
            }
            .padding(.horizontal, 16)

            feedFilterChips

            if vm.visibleFeed.isEmpty {
                if vm.feedFilter == .following {
                    ARInlineEmptyState(
                        icon: "person.2",
                        title: follows.following.isEmpty ? "Follow creators you love" : "Nothing new from people you follow",
                        subtitle: follows.following.isEmpty
                            ? "Their newest AR creations will show up here."
                            : "Check back soon, or discover someone new in For You.",
                        actionTitle: "Discover creators",
                        action: { withAnimation(ARDesign.spring) { vm.feedFilter = .forYou } }
                    )
                } else {
                    ARInlineEmptyState(
                        icon: "sparkles",
                        title: "No artworks yet",
                        subtitle: "Be the first to place an AR creation in the world.",
                        actionTitle: "Create one",
                        action: { dashboardState.path.append(.create) }
                    )
                }
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(vm.visibleFeed) { asset in
                        ARSocialAssetCard(
                            asset: asset,
                            creator: vm.creator(for: asset),
                            isTrending: vm.isTrending(asset),
                            onOpenInAR: { dashboardState.path.append(.viewer) },
                            onOpenCreator: { openProfile(asset.userId) },
                            onOpen: { selectedAsset = asset },
                            onOpenComments: { commentsAsset = asset }
                        )
                        .padding(.horizontal, 16)
                        .onAppear { vm.loadMoreIfNeeded(current: asset) }
                    }

                    if vm.hasMore {
                        ProgressView()
                            .tint(.purple)
                            .padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var feedFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ARExploreViewModel.FeedFilter.allCases) { filter in
                    ARFilterChip(
                        title: filter.rawValue,
                        icon: filter.icon,
                        isActive: vm.feedFilter == filter
                    ) {
                        ARHaptics.tick()
                        withAnimation(ARDesign.spring) {
                            vm.feedFilter = filter
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Featured Card

struct ARFeaturedCard: View {
    let asset: DigitalAsset

    var body: some View {
        HoloCard(intensity: asset.isRareFind ? 1.15 : 0.9) {
            ZStack(alignment: .bottomLeading) {
                AssetThumbnailView(asset: asset, cornerRadius: 0)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipped()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.88)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("\(asset.hypeCount.compactFormatted) hype")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                        if asset.viewCount > 0 {
                            Text("· \(asset.viewCount.compactFormatted) explorers")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))

                    Text(asset.name ?? "Untitled")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let loc = asset.displayLocation {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text(loc)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.purple.opacity(0.3), radius: 20, x: 0, y: 8)
        }
    }
}

// MARK: - Suggested creator card

struct SuggestedCreatorCard: View {
    let suggestion: ARExploreViewModel.SuggestedCreator
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                Group {
                    if let preview = suggestion.preview {
                        AssetThumbnailView(asset: preview, cornerRadius: 0)
                    } else {
                        AppColors.purplePinkGradient
                    }
                }
                .frame(width: 156, height: 70)
                .clipped()
                .overlay(Color.black.opacity(0.15))

                ARAvatarView(url: suggestion.creator.avatarUrl,
                             name: suggestion.creator.displayName, size: 58)
                    .padding(3)
                    .background(Circle().fill(ARDesign.screenBackground))
                    .overlay(Circle().strokeBorder(AppColors.purplePinkGradient, lineWidth: 2))
                    .offset(y: 30)
            }
            .frame(width: 156, height: 70)
            .padding(.bottom, 26)

            VStack(spacing: 2) {
                ARCreatorName(creator: suggestion.creator)
                Text("@\(suggestion.creator.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("\(suggestion.assetCount) creation\(suggestion.assetCount == 1 ? "" : "s") · \(suggestion.totalHype.compactFormatted) hype")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 8)

            ARFollowButton(userId: suggestion.creator.id, style: .prominent)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(width: 156)
        .background(Color.adaptive(light: Color(.systemBackground),
                                   dark: Color(red: 0.10, green: 0.07, blue: 0.18)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(ARDesign.hairline, lineWidth: 1))
        .shadow(color: AppColors.cardShadow, radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open profile", onOpen)
    }
}
