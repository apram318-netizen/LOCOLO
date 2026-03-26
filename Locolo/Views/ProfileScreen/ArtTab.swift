//
//  ArtTab.swift
//  Locolo
//
//  Created by Apramjot Singh on 1/10/2025.
//

import SwiftUI

// MARK: - Asset Navigation Wrapper
// Wrapper struct to make DigitalAsset Hashable for navigation
struct AssetNavigationItem: Identifiable, Hashable {
    let id: UUID
    let asset: DigitalAsset
    
    init(asset: DigitalAsset) {
        self.asset = asset
        self.id = asset.id
    }
    
    static func == (lhs: AssetNavigationItem, rhs: AssetNavigationItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ArtTab: View {
    let assets: [DigitalAsset]
    
    // MARK: Navigation State
    // State for presenting asset detail view
    @State private var selectedAsset: AssetNavigationItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: Header Section
            Text("Digital Collection")
                .font(.headline)
                .padding(.horizontal, 6)

            // MARK: Content Section
            if assets.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                    Text("No artworks yet")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                    Text("Start collecting or minting to see them here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                // MARK: Assets Grid Section
                // Two-column grid like OpenSea/Instagram
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: 10) {
                    ForEach(assets) { asset in
                        Button {
                            selectedAsset = AssetNavigationItem(asset: asset)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: URL(string: asset.thumbUrl ?? asset.fileUrl)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.gray.opacity(0.15)
                                    }
                                    .frame(height: 160)
                                    .clipped()
                                    .cornerRadius(14)
                                    
                                    if asset.interactionType == "ar" {
                                        Text("AR")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(Color.purple.opacity(0.9))
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                            .padding(8)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.name ?? "Untitled")
                                        .font(.headline)
                                        .lineLimit(1)
                                    if let category = asset.category {
                                        Text(category)
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                    }
                                }
                                
                                HStack {
                                    Label("\(asset.hypeCount)", systemImage: "bolt.fill")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                    Spacer()
                                    Text(asset.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .background(Color(.systemBackground))
                            .cornerRadius(14)
                            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 6) //  small consistent side padding
                .padding(.bottom, 80)
            }
        }
        // MARK: Asset Detail Navigation
        // Presents asset detail sheet when an asset is tapped
        .navigationDestination(item: $selectedAsset) { item in
            AssetDetailSheet(asset: item.asset)
        }
    }
}
