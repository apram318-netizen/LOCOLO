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
        .background(Color.adaptive(
            light: Color(.systemBackground),
            dark: Color(red: 0.10, green: 0.07, blue: 0.18)
        ))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(ARDesign.hairline, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadow, radius: 18, x: 0, y: 6)
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
            ShareLink(item: DeepLinkRouter.assetURL(for: asset.id),
                      subject: Text(asset.name ?? "AR creation"),
                      message: Text("Check out \(asset.name ?? "this AR creation") on Locolo")) {
                Label("Share…", systemImage: "square.and.arrow.up")
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
            AssetThumbnailView(asset: asset, cornerRadius: 0)
                .aspectRatio(4 / 3, contentMode: .fit)

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

            ShareLink(item: DeepLinkRouter.assetURL(for: asset.id),
                      subject: Text(asset.name ?? "AR creation"),
                      message: Text("Check out \(asset.name ?? "this AR creation") on Locolo")) {
                Image(systemName: "paperplane")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
            }
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
