//
//  CollectionView.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI

struct CollectionView: View {
    
    var searchQuery: String = ""
    
    @EnvironmentObject var userVM: UserViewModel
    @StateObject private var vm = CollectionViewModel()
    
    @State private var selectedAsset: DigitalAsset?
    @State private var filterBy: String = "all"    // current rarity filter
    
    
    // MARK: Filtered Logic
    // This combines search text + rarity filter to produce the displayed list.
    var filteredCollection: [DigitalAsset] {
        vm.assets.filter { asset in
            let matchesSearch =
            searchQuery.isEmpty ||
            asset.name?.localizedCaseInsensitiveContains(searchQuery) == true ||
            asset.category?.localizedCaseInsensitiveContains(searchQuery) == true
            
            let matchesFilter = filterBy == "all" || asset.visibility == filterBy
            return matchesSearch && matchesFilter
        }
    }
    
    
    // MARK: Body
    var body: some View {
        VStack(spacing: 16) {
            
            // MARK: Header Section
            HStack {
                Text("My Collection")
                    .font(.headline)
                    .foregroundColor(AppColors.primaryText)
                
                Spacer()
                
                Text("\(filteredCollection.count) pieces")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(colors: [.blue, .cyan],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )
                    .cornerRadius(12)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            
            
            // MARK: Filter Buttons Section
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
            
            
            // MARK: Items Section
            ScrollView {
                if vm.isLoading {
                    // loading state
                    ProgressView("Loading your collection...")
                        .padding()
                    
                } else if let error = vm.errorMessage {
                    // error state
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                    
                } else if filteredCollection.isEmpty {
                    // empty collection
                    Text("You don’t own any assets yet.")
                        .foregroundColor(.gray)
                        .padding()
                    
                } else {
                    // list of assets
                    VStack(spacing: 16) {
                        ForEach(filteredCollection) { asset in
                            Button {
                                selectedAsset = asset
                            } label: {
                                CollectionCard(asset: asset)
                            }
                            .buttonStyle(PlainButtonStyle())   // removes blue tint
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(AppColors.screenBackground.ignoresSafeArea())
            .task {
                // loads collection when view appears
                if let user = userVM.currentUser {
                    await vm.loadUserCollection(userId: user.id)
                }
            }
            .sheet(item: $selectedAsset) { asset in
                AssetDetailSheet(asset: asset)
            }
        }
    }
}


// MARK: - Card Component
// This draws one asset preview including thumbnail, name,
// category, rarity tag, stats, date, and sell button.

struct CollectionCard: View {
    let asset: DigitalAsset
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            
            // Thumbnail
            AsyncImage(url: URL(string: asset.thumbUrl ?? asset.fileUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 80, height: 80)
            .cornerRadius(12)

            
            VStack(alignment: .leading, spacing: 8) {
                
                // Name, category, rarity tag
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.name ?? "Untitled")
                            .font(.headline)
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(asset.category ?? "Unknown Category")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Text(asset.visibility.capitalized ?? "Normal")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.rarityGradient(asset.visibility ?? "normal"))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }

                
                // Hype + view stats
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("Hypes")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(asset.hypeCount ?? 0)")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(AppColors.primaryText)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Views")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Text("\(asset.viewCount ?? 0)")
                            .font(.subheadline)
                            .bold()
                            .foregroundColor(AppColors.primaryText)
                    }
                }

                
                // Date + Sell button
                HStack {
                    Text(asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                }
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: AppColors.cardShadow, radius: 2, x: 0, y: 1)
    }
}


// MARK: - Filter Button
// This is used for the rarity filter row at the top.

struct FilterButton: View {
    let title: String
    let isActive: Bool
    let gradient: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.capitalized)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Group {
                        if isActive {
                            gradient
                        } else {
                            AppColors.cardBackground
                        }
                    }
                )
                .cornerRadius(12)
                .foregroundColor(isActive ? .white : AppColors.secondaryText)
        }
    }
}
