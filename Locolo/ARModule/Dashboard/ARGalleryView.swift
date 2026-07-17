//
//  ARGalleryView.swift
//  Locolo
//
//  ArtworkCard: the compact list card used by the Search tab's results.
//  (The old ARGalleryView screen was absorbed into ARSearchView.)
//

import SwiftUI
import CoreLocation

// MARK: - ArtworkCard
struct ArtworkCard: View {
    let asset: DigitalAsset
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @EnvironmentObject var userVM: UserViewModel

    @State private var isWishlisted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack(spacing: 12) {
                // Thumbnail
                AssetThumbnailView(asset: asset)
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name ?? "Untitled")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(asset.category?.capitalized ?? "Uncategorized")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(asset.distanceLabel ?? "--")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                Spacer()

                // Wishlist Button
                Button {
                    toggleWishlist()
                } label: {
                    Image(systemName: isWishlisted ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundColor(isWishlisted ? .red : AppColors.secondaryText)
                        .padding(6)
                }
                .accessibilityLabel(isWishlisted ? "Remove from wishlist" : "Save to wishlist")
            }

            // Bottom stats
            HStack(spacing: 12) {
                Label("\(asset.viewCount) views", systemImage: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.gray)

                Label("\(asset.hypeCount) hypes", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.gray)

                if let loc = asset.displayLocation {
                    Label(loc, systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColors.cardShadow, radius: 5, x: 0, y: 2)
        .padding(.horizontal)
        .onAppear {
            isWishlisted = wishlistVM.items.contains(where: { $0.id == asset.id })
        }
    }

    // MARK: - Wishlist Toggle
    private func toggleWishlist() {
        guard let currentUser = userVM.currentUser else { return }
        ARHaptics.tick()
        let wasWishlisted = isWishlisted
        isWishlisted.toggle()
        Task {
            if wasWishlisted {
                await wishlistVM.removeFromWishlist(userId: currentUser.id, assetId: asset.id)
            } else {
                await wishlistVM.addToWishlist(userId: currentUser.id, assetId: asset.id)
            }
        }
    }
}
