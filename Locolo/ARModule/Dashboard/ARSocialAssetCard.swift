//
//  ARSocialAssetCard.swift
//  Locolo
//
//  The Explore feed's social card: creator row (with inline follow + overflow
//  menu), media preview (double-tap to hype), an action row (hype, comment,
//  share, save, open in AR) and the caption block. Hype and comment counts
//  come from EngagementStore so every surface stays in sync.
//

import SwiftUI

struct ARSocialAssetCard: View {
    let asset: DigitalAsset
    var creator: ARCreator?
    var isTrending = false
    /// Push the AR viewer (only offered when the asset is physically nearby).
    var onOpenInAR: (() -> Void)? = nil
    /// Open the creator's public profile (WS4).
    var onOpenCreator: (() -> Void)? = nil
    /// Open the detail sheet (single tap on media or caption).
    var onOpen: (() -> Void)? = nil
    /// Open the comment thread.
    var onOpenComments: (() -> Void)? = nil

    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @ObservedObject private var engagement = EngagementStore.shared
    @ObservedObject private var follows = FollowStore.shared
    @ObservedObject private var reposts = RepostStore.shared

    @State private var isWishlisted = false
    @State private var burst = false
    @State private var showReport = false
    @State private var showSaveToBoard = false
    @State private var sharePayload: ARSharePayload?

    private var isHyped: Bool { engagement.isHyped(asset.id) }
    private var hypeCount: Int { engagement.hypeCount(for: asset) }
    private var commentCount: Int { engagement.commentCount(for: asset.id) }
    private var isReposted: Bool { reposts.isReposted(asset.id) }
    private var repostCount: Int { reposts.count(for: asset.id) }
    private var isMine: Bool { userVM.currentUser?.id == asset.userId }

    /// The viewer places assets around you, so only offer "Open in AR"
    /// within the same radius the detail sheet uses.
    private var isCloseEnoughForAR: Bool {
        guard let meters = asset.distanceMeters else { return false }
        return meters <= 150
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            creatorRow
            mediaSection
            actionRow
            captionSection
        }
        // Instagram-style: edge-to-edge post, no floating card chrome, so the
        // media uses the full screen width (V3 feedback).
        .background(ARDesign.screenBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(ARDesign.hairline).frame(height: 0.5) }
        .sheet(item: $sharePayload) { ARShareSheet(payload: $0) }
        .onAppear {
            isWishlisted = wishlistVM.items.contains { $0.id == asset.id }
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(assetId: asset.id, userId: asset.userId,
                        subjectName: asset.name ?? "this creation")
        }
        .sheet(isPresented: $showSaveToBoard) {
            SaveToBoardSheet(asset: asset)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Creator row

    private var creatorRow: some View {
        HStack(spacing: 10) {
            Button { onOpenCreator?() } label: {
                HStack(spacing: 10) {
                    ARAvatarView(url: creator?.avatarUrl, name: creator?.displayName ?? "?", size: 36)
                        .padding(2)
                        .overlay(Circle().strokeBorder(AppColors.purplePinkGradient, lineWidth: 1.5))

                    VStack(alignment: .leading, spacing: 1) {
                        ARCreatorName(creator: creator, fallback: "AR Creator")
                        Text(subtitleLine)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(creator?.displayName ?? "creator")'s profile")

            Spacer(minLength: 6)

            if isTrending {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption2)
                    Text("Trending").font(.caption2.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppColors.trendingBadge))
                .accessibilityLabel("Trending asset")
            }

            if !isMine && follows.isLoaded && !follows.isFollowing(asset.userId) {
                ARFollowButton(userId: asset.userId, style: .compact)
            }

            overflowMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var subtitleLine: String {
        var parts = [asset.createdAt.shortRelative]
        if let loc = asset.locationName ?? asset.displayLocation, !loc.isEmpty { parts.append(loc) }
        return parts.joined(separator: " · ")
    }

    private var overflowMenu: some View {
        Menu {
            Button { sharePayload = .asset(asset) } label: {
                Label("Send to friends…", systemImage: "paperplane")
            }
            ShareLink(item: DeepLinkRouter.assetURL(for: asset.id),
                      subject: Text(asset.name ?? "AR creation"),
                      message: Text("Check out \(asset.name ?? "this AR creation") on Locolo")) {
                Label("Share externally…", systemImage: "square.and.arrow.up")
            }
            Button {
                UIPasteboard.general.url = DeepLinkRouter.assetURL(for: asset.id)
                ARHaptics.success()
            } label: {
                Label("Copy link", systemImage: "link")
            }
            if onOpenCreator != nil {
                Button { onOpenCreator?() } label: {
                    Label("View creator", systemImage: "person.crop.circle")
                }
            }
            Button { showSaveToBoard = true } label: {
                Label("Save to board", systemImage: "square.stack.3d.up")
            }
            if !isMine {
                Divider()
                Button(role: .destructive) { showReport = true } label: {
                    Label("Report", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: - Media

    private var mediaSection: some View {
        ZStack(alignment: .bottom) {
            AssetPostMedia(asset: asset)

            LinearGradient(colors: [.clear, Color.black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                if let dist = asset.distanceLabel {
                    mediaPill(icon: "location.fill", text: dist, fill: Color.black.opacity(0.45))
                }
                Spacer()
                if let cat = asset.categoryLabel {
                    mediaPill(icon: nil, text: cat, fill: Color.purple.opacity(0.65))
                }
            }
            .padding(12)
            .allowsHitTesting(false)

            Image(systemName: "bolt.fill")
                .font(.system(size: 86, weight: .black))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .pink],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 12)
                .scaleEffect(burst ? 1.0 : 0.3)
                .opacity(burst ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { doubleTapHype() }
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(asset.name ?? "AR creation")
        .accessibilityHint("Double tap to open. Use actions to hype.")
        .accessibilityAction(named: "Hype") { Task { await engagement.toggleHype(asset) } }
    }

    private func mediaPill(icon: String?, text: String, fill: Color) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.caption2.weight(.semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(fill))
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button {
                ARHaptics.tick()
                Task { await engagement.toggleHype(asset) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isHyped ? "bolt.fill" : "bolt")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isHyped
                                         ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange],
                                                                        startPoint: .top, endPoint: .bottom))
                                         : AnyShapeStyle(Color.primary))
                        .symbolEffect(.bounce, value: isHyped)
                    Text(hypeCount.compactFormatted)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHyped ? "Hyped, \(hypeCount) hypes. Double tap to remove" : "Hype, \(hypeCount) hypes")

            if engagement.commentsAvailable {
                Button { onOpenComments?() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.right")
                            .font(.title3.weight(.semibold))
                        Text(commentCount.compactFormatted)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Comments, \(commentCount)")
            }

            if reposts.available {
                Button {
                    ARHaptics.tick()
                    Task { await reposts.toggle(asset) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isReposted ? "arrow.2.squarepath" : "arrow.2.squarepath")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(isReposted ? .green : .primary)
                        if repostCount > 0 {
                            Text(repostCount.compactFormatted)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(.primary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isReposted ? "Undo re-drop" : "Re-drop")
            }

            Button { sharePayload = .asset(asset) } label: {
                Image(systemName: "paperplane")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            Spacer()

            if isCloseEnoughForAR, let onOpenInAR {
                Button(action: onOpenInAR) {
                    HStack(spacing: 5) {
                        Image(systemName: "arkit")
                        Text("View in AR")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(AppColors.purplePinkGradient))
                }
                .accessibilityLabel("Open in AR")
            }

            Button(action: toggleWishlist) {
                Image(systemName: isWishlisted ? "bookmark.fill" : "bookmark")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(isWishlisted ? .purple : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isWishlisted ? "Remove from saved" : "Save")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    // MARK: - Caption

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(asset.name ?? "Untitled")
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            if let desc = asset.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                if engagement.commentsAvailable && commentCount > 0 {
                    Button { onOpenComments?() } label: {
                        Text(commentCount == 1 ? "View 1 comment" : "View all \(commentCount) comments")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                if asset.viewCount > 0 {
                    Label("\(asset.viewCount.compactFormatted) explorers", systemImage: "eye")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }

    // MARK: - Helpers

    private func doubleTapHype() {
        ARHaptics.success()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.25)) { burst = false }
        }
        Task { await engagement.hypeIfNeeded(asset) }
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
                await wishlistVM.addToWishlist(userId: user.id, assetId: asset.id)
            }
        }
    }
}


// MARK: - Post media stage

/// Full-width 4:5 post media. Instead of a cropped thumbnail on flat black,
/// the asset floats on a stage: its own colours as an aurora, a blurred
/// echo of the artwork filling the frame, and the artwork itself fitted
/// (never cropped) with a soft shadow and floor glow.
struct AssetPostMedia: View {
    let asset: DigitalAsset
    @State private var palette = AssetStageBackground.defaultPalette

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.78
            ZStack {
                AssetStageBackground(palette: palette)
                AssetThumbnailView(asset: asset, cornerRadius: 0)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 40)
                    .opacity(0.45)
                    .blendMode(.screen)
                Ellipse()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: side * 0.8, height: side * 0.12)
                    .blur(radius: 14)
                    .offset(y: side * 0.52)
                AssetThumbnailView(asset: asset, cornerRadius: 22)
                    .frame(width: side, height: side)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: palette[0].opacity(0.55), radius: 26, y: 12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .task(id: asset.id) {
            if let colors = await AssetStageBackground.palette(for: asset) {
                withAnimation(.easeInOut(duration: 0.5)) { palette = colors }
            }
        }
    }
}
