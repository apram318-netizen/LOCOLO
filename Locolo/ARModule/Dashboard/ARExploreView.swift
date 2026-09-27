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

    @State private var selectedAsset: DigitalAsset?
    @State private var featuredPage = 0

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
                            featuredSection
                            feedSection
                        }
                        .padding(.bottom, 24)
                    }
                }
                .refreshable { await vm.refresh() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ARGlassHeader(title: "AR World", subtitle: "Shared Creative Space", onExit: onDismiss) {
                HStack(spacing: 8) {
                    ARHeaderIconButton(icon: "bubble.left.and.bubble.right", label: "Messages") {
                        dashboardState.path.append(.conversations)
                    }
                    ARHeaderIconButton(icon: "arkit", label: "Open AR viewer") {
                        dashboardState.path.append(.viewer)
                    }
                    ARHeaderIconButton(icon: "plus", label: "Create AR asset", prominent: true) {
                        dashboardState.path.append(.create)
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(asset: asset, onOpenCreator: {
                dashboardState.path.append(.profile(userId: asset.userId))
            })
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ARLoadingView(message: "Loading AR World…")
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
            ARSectionHeader(
                title: "Shared Space",
                subtitle: "AR art placed around the world",
                icon: "globe.americas.fill"
            )
            .padding(.horizontal, 16)
            .padding(.top, 24)

            feedFilterChips

            if vm.visibleFeed.isEmpty {
                ARInlineEmptyState(
                    icon: "sparkles",
                    title: "No artworks yet",
                    subtitle: "Be the first to place an AR creation in the world.",
                    actionTitle: "Create one",
                    action: { dashboardState.path.append(.create) }
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(vm.visibleFeed) { asset in
                        ARSocialAssetCard(
                            asset: asset,
                            creator: vm.creator(for: asset),
                            isTrending: vm.isTrending(asset),
                            onOpenInAR: { dashboardState.path.append(.viewer) },
                            onOpenCreator: { dashboardState.path.append(.profile(userId: asset.userId)) }
                        )
                        .padding(.horizontal, 16)
                        .onTapGesture { selectedAsset = asset }
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
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(asset.engagementScore) hype")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
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
