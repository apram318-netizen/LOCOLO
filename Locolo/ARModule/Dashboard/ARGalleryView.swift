//
//  ARGalleryView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI
import CoreLocation
import Foundation

// MARK: - ARGalleryView
struct ARGalleryView: View {
    @StateObject private var vm: ARGalleryViewModel
    var searchQuery: String = ""
    
    // New state for selected artwork
    @State private var selectedAsset: DigitalAsset?

    init(searchQuery: String = "") {
        _vm = StateObject(wrappedValue: ARGalleryViewModel())
        self.searchQuery = searchQuery
    }

    var body: some View {
        VStack(spacing: 16) {
            // Category Filters
            categoryFilters

            Divider().padding(.horizontal)
            
            // Artwork List
            ScrollView {
                contentView
            }
        }
        .task { await vm.loadArtworks() }
        .background(AppColors.screenBackground.ignoresSafeArea())
        // Open sheet when an artwork is selected
        .sheet(item: $selectedAsset) { asset in
            AssetDetailSheet(asset: asset)
        }
    }

    // MARK: - Category Filters
    private var categoryFilters: some View {
        HStack(spacing: 10) {
            ForEach(["all", "art", "photo", "3d", "audio"], id: \.self) { category in
                Button {
                    vm.selectedCategory = category
                } label: {
                    Text(category.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Group {
                                if vm.selectedCategory == category {
                                    LinearGradient(colors: [.purple, .pink],
                                                   startPoint: .leading,
                                                   endPoint: .trailing)
                                } else {
                                    AppColors.cardBackground
                                }
                            }
                        )
                        .cornerRadius(10)
                        .foregroundColor(vm.selectedCategory == category ? .white : AppColors.secondaryText)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Content Section
    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading {
            ProgressView("Loading artworks...")
                .padding(.top)
        } else if let error = vm.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .padding()
        } else if filteredArtworks.isEmpty {
            Text("No artworks found.")
                .foregroundColor(.gray)
                .padding(.top)
        } else {
            VStack(spacing: 16) {
                Text("\(filteredArtworks.count) artworks found")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.top, 8)
                
                ForEach(filteredArtworks) { art in
                    Button {
                        selectedAsset = art
                    } label: {
                        ArtworkCard(asset: art)
                    }
                    .buttonStyle(PlainButtonStyle()) // removes default blue tint
                }
            }
        }
    }

    // MARK: - Filtered Artworks (includes external searchQuery)
    private var filteredArtworks: [DigitalAsset] {
        vm.artworks.filter { art in
            let matchesSearch =
                searchQuery.isEmpty ||
                (art.description ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                (art.category ?? "").localizedCaseInsensitiveContains(searchQuery)
            
            let matchesCategory =
                vm.selectedCategory == "all" ||
                (art.category?.lowercased() == vm.selectedCategory.lowercased())
            
            return matchesSearch && matchesCategory
        }
    }
}


// MARK: - ArtworkCard
struct ArtworkCard: View {
    let asset: DigitalAsset
    @EnvironmentObject var wishlistVM: WishlistViewModel
    @EnvironmentObject var userVM: UserViewModel
    
    @State private var isWishlisted = false
    
    
    private var distanceText: String {
        guard let lat = asset.latitude,
              let lon = asset.longitude else { return "--" }

        let manager = LocationManager.shared

        // live or fallback location
        guard let coord = manager.userLocation ?? manager.latestStoredLocation else {
            return "--"
        }

        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let assetLoc = CLLocation(latitude: lat, longitude: lon)

        let meters = userLoc.distance(from: assetLoc)

        if meters < 100 {
            return "\(Int(meters)) m"
        } else if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }


    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            HStack(spacing: 12) {
                // Thumbnail
                AsyncImage(url: URL(string: asset.thumbUrl ?? asset.fileUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    AppColors.secondaryText.opacity(0.3)
                }
                .frame(width: 80, height: 80)
                .cornerRadius(12)
                
                
                // TEXT
                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name ?? "Untitled")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)

                    Text(asset.category ?? "Uncategorized")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)

                    // DISTANCE INSTEAD OF PRICE
                    Text(distanceText)
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
            }
            
            
            // Bottom stats
            HStack(spacing: 12) {

                
                if let lat = asset.latitude,
                   let lon = asset.longitude {
                    Label("Loc: \(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))",
                          systemImage: "location.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
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
        
        if isWishlisted {
            Task {
                await wishlistVM.removeFromWishlist(userId: currentUser.id, assetId: asset.id)
                isWishlisted = false
            }
        } else {
            Task {
                await wishlistVM.addToWishlist(userId: currentUser.id, assetId: asset.id)
                isWishlisted = true
            }
        }
    }
    
}
