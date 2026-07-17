//
//  ARSocialAssetCard.swift
//  Locolo
//
//  The Explore feed's social card: creator row, media preview with
//  badges, title/description, and an action row (hype, save to
//  wishlist, share, open in AR). Replaces the old ARWorldFeedCard.
//

import SwiftUI

struct ARSocialAssetCard: View {
    let asset: DigitalAsset
    var creator: ARCreator?
    var isTrending = false
    /// Push the AR viewer (only offered when the asset is physically nearby).
    var onOpenInAR: (() -> Void)? = nil

    @EnvironmentObject var userVM: UserViewModel
    @EnvironmentObject var wishlistVM: WishlistViewModel

    @State private var isWishlisted = false

    /// The viewer places assets around you, so only offer "Open in AR"
    /// within the same radius the detail sheet uses.
    private var isCloseEnoughForAR: Bool {
        guard let meters = asset.distanceMeters else { return false }
        return meters <= 150
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            creatorRow
            thumbnailSection
            contentSection
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
    }

    // MARK: - Creator row

    private var creatorRow: some View {
        HStack(spacing: 10) {
            AsyncImage(url: creator?.avatarUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Circle().fill(Color.purple.opacity(0.2))
                    Image(systemName: "person.fill")
                        .font(.caption)
                        .foregroundColor(.purple)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(creator?.displayName ?? "AR Creator")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if creator?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified creator")
                    }
                }
                Text(asset.createdAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isTrending {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                    Text("Trending")
                        .font(.caption2.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(AppColors.trendingBadge))
                .accessibilityLabel("Trending asset")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Thumbnail

    private var thumbnailSection: some View {
        ZStack(alignment: .bottom) {
            AssetThumbnailView(asset: asset, cornerRadius: 0)
                .aspectRatio(16 / 9, contentMode: .fit)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(locationLabel)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundColor(.white.opacity(0.9))

                Spacer()

                if let dist = asset.distanceLabel {
                    Text(dist)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }

                if let cat = asset.category {
                    Text(cat.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.6)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Content + actions

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            HStack(spacing: 18) {
                statItem(icon: "bolt.fill", value: asset.hypeCount, label: "hypes", color: .yellow)
                statItem(icon: "eye.fill", value: asset.viewCount, label: "views", color: .secondary)

                Spacer()

                Button(action: toggleWishlist) {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isWishlisted ? .pink : .secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(ARDesign.headerButtonCircle))
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(isWishlisted ? "Remove from wishlist" : "Save to wishlist")

                if let url = URL(string: asset.fileUrl) {
                    ShareLink(item: url, subject: Text(asset.name ?? "AR Asset")) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(ARDesign.headerButtonCircle))
                    }
                    .accessibilityLabel("Share asset")
                }

                if isCloseEnoughForAR, let onOpenInAR {
                    Button(action: onOpenInAR) {
                        HStack(spacing: 5) {
                            Image(systemName: "arkit")
                            Text("Open")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(AppColors.purplePinkGradient))
                    }
                    .accessibilityLabel("Open in AR")
                }
            }
        }
        .padding(14)
    }

    private func statItem(icon: String, value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    // MARK: - Helpers

    private var locationLabel: String {
        if let loc = asset.displayLocation { return loc }
        if let lat = asset.latitude, let lon = asset.longitude {
            return String(format: "%.3f°, %.3f°", lat, lon)
        }
        return "Unknown location"
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
