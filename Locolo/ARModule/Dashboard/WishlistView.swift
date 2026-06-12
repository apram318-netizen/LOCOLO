//
//  WishlistView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI

struct WishlistItem: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let price: String
    let image: String
    let rarity: String
}


// MARK: - Offer Asset ID Wrapper
// Wrapper struct to make UUID Identifiable for sheet presentation
struct OfferAssetId: Identifiable {
    let id: UUID
}

struct WishlistView: View {
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var vm = WishlistViewModel()
    @State private var filterBy: String = "all"

    var searchQuery: String = ""
    
    // MARK: Sheet State
    // State for presenting asset detail and create offer sheets
    @State private var selectedAsset: DigitalAsset?
    @State private var offerAssetId: OfferAssetId?

    // Filtering
    var filteredWishlist: [DigitalAsset] {
        vm.items.filter { asset in
            let matchesSearch =
                searchQuery.isEmpty ||
                asset.name?.localizedCaseInsensitiveContains(searchQuery) == true ||
                asset.category?.localizedCaseInsensitiveContains(searchQuery) == true

            let matchesFilter = filterBy == "all" || asset.visibility == filterBy
            return matchesSearch && matchesFilter
        }
    }
    
    // MARK: Check if asset belongs to current user
    // Returns true if the asset's owner is the current user
    private func isOwnAsset(_ asset: DigitalAsset) -> Bool {
        guard let currentUser = userVM.currentUser else { return false }
        return asset.userId == currentUser.id
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Wishlist")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Text("\(filteredWishlist.count) items")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [.pink, .red],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)

            // Filter buttons
            HStack {
                ForEach(["all", "normal", "rare", "legendary"], id: \.self) { filter in
                    FilterButton(
                        title: filter,
                        isActive: filterBy == filter,
                        gradient: AppColors.rarityGradient(filter),
                        action: { filterBy = filter }
                    )
                }
            }
            .padding(.horizontal)

            // Wishlist List
            ScrollView {
                if vm.isLoading {
                    ProgressView("Loading your wishlist...")
                        .padding()
                } else if let error = vm.errorMessage {
                    Text(error).foregroundColor(.red).padding()
                } else if filteredWishlist.isEmpty {
                    Text("No items in your wishlist yet.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    VStack(spacing: 16) {
                        ForEach(filteredWishlist) { asset in
                            WishlistCard(
                                asset: asset,
                                isOwnAsset: isOwnAsset(asset),
                                onCardTap: {
                                    selectedAsset = asset
                                },
                                onOffer: {
                                    // Create wrapper and set it, which will trigger sheet presentation
                                    offerAssetId = OfferAssetId(id: asset.id)
                                },
                                onRemove: {
                                    Task {
                                        if let user = userVM.currentUser {
                                            await vm.removeFromWishlist(userId: user.id, assetId: asset.id)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(AppColors.screenBackground.ignoresSafeArea())
        .task {
            if let user = userVM.currentUser {
                await vm.loadWishlist(for: user.id)
            }
        }
        // MARK: Asset Detail Sheet
        // Presents asset detail view when card is tapped
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(asset: asset)
                .environmentObject(userVM)
        }
        // MARK: Create Offer Sheet
        // Presents create offer view when offer button is tapped using item-based presentation
        .sheet(item: $offerAssetId) { item in
            CreateOfferView(assetId: item.id)
                .environmentObject(userVM)
        }
    }
}

struct WishlistCard: View {
    let asset: DigitalAsset
    let isOwnAsset: Bool
    let onCardTap: () -> Void
    let onOffer: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onCardTap) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: asset.thumbUrl ?? asset.fileUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(asset.name ?? "Untitled")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                    Text(asset.category ?? "Uncategorized")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)

                    HStack(spacing: 8) {
                        Text(asset.visibility.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.rarityGradient(asset.visibility ))
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    // MARK: Conditional Offer Button
                    // Only show offer button if asset doesn't belong to current user
                    if !isOwnAsset {
                        Button(action: onOffer) {
                            Text("Offer")
                                .font(.caption)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(colors: [.purple, .pink],
                                                   startPoint: .leading,
                                                   endPoint: .trailing)
                                )
                                .cornerRadius(14)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(8)
                            .background(AppColors.cardBackground)
                            .clipShape(Circle())
                            .shadow(color: AppColors.cardShadow, radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(AppColors.cardBackground)
            .cornerRadius(20)
            .shadow(color: AppColors.cardShadow, radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
