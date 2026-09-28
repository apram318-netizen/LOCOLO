//
//  ImmersiveFeedView.swift
//  Locolo
//
//  Phase D: full-screen vertical For You pager (TikTok-style). One asset per
//  screen — media fills the viewport, actions on the right, caption + place
//  at the bottom. Hype/comments/wishlist go through the shared stores.
//

import SwiftUI

struct ImmersiveFeedView: View {
    let assets: [DigitalAsset]
    var creatorFor: (DigitalAsset) -> ARCreator?
    var isTrending: (DigitalAsset) -> Bool
    var onClose: () -> Void
    var onOpenCreator: (UUID) -> Void
    var onOpenInAR: () -> Void
    var onNearEnd: ((DigitalAsset) -> Void)?

    @State private var commentsAsset: DigitalAsset?
    @State private var detailAsset: DigitalAsset?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if assets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Nothing to swipe yet")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Drop something, or switch back to the list.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                    Button("Back to list", action: onClose)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .padding(.top, 8)
                }
                .padding(32)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(assets) { asset in
                            ImmersiveFeedPage(
                                asset: asset,
                                creator: creatorFor(asset),
                                isTrending: isTrending(asset),
                                onOpenCreator: { onOpenCreator(asset.userId) },
                                onOpenInAR: onOpenInAR,
                                onOpenComments: { commentsAsset = asset },
                                onOpenDetail: { detailAsset = asset }
                            )
                            .containerRelativeFrame(.vertical)
                            .onAppear { onNearEnd?(asset) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.body.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(.white.opacity(0.18)))
                    }
                    .accessibilityLabel("Close immersive feed")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden()
        .sheet(item: $commentsAsset) { asset in
            CommentsSheet(asset: asset, onOpenProfile: { onOpenCreator($0) })
        }
        .sheet(item: $detailAsset) { asset in
            AssetDetailSheet(
                asset: asset,
                onOpenCreator: { onOpenCreator(asset.userId) },
                onOpenProfile: { onOpenCreator($0) }
            )
        }
    }
}

// MARK: - Page

private struct ImmersiveFeedPage: View {
    let asset: DigitalAsset
    var creator: ARCreator?
    var isTrending: Bool
    var onOpenCreator: () -> Void
    var onOpenInAR: () -> Void
    var onOpenComments: () -> Void
    var onOpenDetail: () -> Void

    @EnvironmentObject private var userVM: UserViewModel
    @EnvironmentObject private var wishlistVM: WishlistViewModel
    @ObservedObject private var engagement = EngagementStore.shared
    @ObservedObject private var follows = FollowStore.shared

    @State private var isWishlisted = false
    @State private var burst = false
    @State private var showSaveToBoard = false
    @State private var celebrateSave = false

    private var isHyped: Bool { engagement.isHyped(asset.id) }
    private var hypeCount: Int { engagement.hypeCount(for: asset) }
    private var commentCount: Int { engagement.commentCount(for: asset.id) }
    private var isMine: Bool { userVM.currentUser?.id == asset.userId }

    private var isCloseEnoughForAR: Bool {
        guard let meters = asset.distanceMeters else { return false }
        return meters <= 150
    }

    var body: some View {
        ZStack {
            AssetThumbnailView(asset: asset, cornerRadius: 0)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            if burst {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 96, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .pink],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 16)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    captionBlock
                    ReactionBarView(assetId: asset.id, compact: true)
                        .frame(maxWidth: 220)
                }
                actionRail
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTapHype() }
        .onTapGesture { onOpenDetail() }
        .onAppear {
            isWishlisted = wishlistVM.items.contains { $0.id == asset.id }
            Task { await ReactionStore.shared.prime([asset]) }
        }
        .sheet(isPresented: $showSaveToBoard) {
            SaveToBoardSheet(asset: asset)
        }
        .celebration(trigger: $celebrateSave, symbol: "square.stack.3d.up.fill")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(asset.name ?? "AR creation")
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenCreator) {
                HStack(spacing: 10) {
                    ARAvatarView(url: creator?.avatarUrl,
                                 name: creator?.displayName ?? "Creator", size: 36)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(creator?.displayName ?? "Creator")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        if let handle = creator?.username {
                            Text("@\(handle)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    if !isMine && follows.isLoaded && !follows.isFollowing(asset.userId) {
                        ARFollowButton(userId: asset.userId, style: .compact)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(asset.name ?? "Untitled")
                .font(.title3.bold())
                .foregroundColor(.white)
                .lineLimit(2)

            if let desc = asset.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if let loc = asset.displayLocation {
                    Label(loc, systemImage: "location.fill")
                        .lineLimit(1)
                }
                Text(asset.createdAt.shortRelative)
                if isTrending {
                    Label("Trending", systemImage: "flame.fill")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRail: some View {
        VStack(spacing: 18) {
            railButton(
                icon: isHyped ? "bolt.fill" : "bolt",
                label: hypeCount.compactFormatted,
                tint: isHyped ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange],
                                                             startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white)
            ) {
                ARHaptics.tick()
                Task { await engagement.toggleHype(asset) }
            }
            .accessibilityLabel(isHyped ? "Unhype" : "Hype")

            if engagement.commentsAvailable {
                railButton(icon: "bubble.right", label: commentCount.compactFormatted) {
                    onOpenComments()
                }
                .accessibilityLabel("Comments")
            }

            ShareLink(item: DeepLinkRouter.assetURL(for: asset.id),
                      subject: Text(asset.name ?? "AR creation"),
                      message: Text("Check out \(asset.name ?? "this AR creation") on Locolo")) {
                railGlyph(icon: "paperplane", label: "Share")
            }
            .accessibilityLabel("Share")

            railButton(icon: isWishlisted ? "bookmark.fill" : "bookmark",
                       label: "Save") {
                toggleWishlist()
            }
            .accessibilityLabel(isWishlisted ? "Remove from wishlist" : "Save to wishlist")

            if BoardsStore.shared.available {
                railButton(icon: "square.stack.3d.up", label: "Board") {
                    showSaveToBoard = true
                    celebrateSave = true
                }
                .accessibilityLabel("Save to board")
            }

            if isCloseEnoughForAR {
                Button(action: onOpenInAR) {
                    Image(systemName: "arkit")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(AppColors.purplePinkGradient))
                }
                .accessibilityLabel("Open in AR")
            }
        }
        .padding(.bottom, 8)
    }

    private func railButton(icon: String, label: String,
                            tint: AnyShapeStyle = AnyShapeStyle(Color.white),
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            railGlyph(icon: icon, label: label, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func railGlyph(icon: String, label: String,
                           tint: AnyShapeStyle = AnyShapeStyle(Color.white)) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
        }
    }

    private func doubleTapHype() {
        guard !isHyped else { return }
        ARHaptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { burst = true }
        Task {
            await engagement.toggleHype(asset)
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.2)) { burst = false }
        }
    }

    private func toggleWishlist() {
        guard let user = userVM.currentUser else { return }
        ARHaptics.tick()
        let wasWishlisted = isWishlisted
        isWishlisted.toggle()
        Task {
            if wasWishlisted {
                await wishlistVM.removeFromWishlist(userId: user.id, assetId: asset.id)
            } else {
                await wishlistVM.addToWishlist(userId: user.id, assetId: asset.id, asset: asset)
            }
        }
    }
}
