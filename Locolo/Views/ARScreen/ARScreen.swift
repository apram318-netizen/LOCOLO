//
//  ARScreen.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI

struct ARScreen: View {
    @State private var activeSection = "gallery"
    @State private var searchQuery = ""
    @EnvironmentObject var wishlistVM :WishlistViewModel
    @EnvironmentObject var userVM :UserViewModel
    var body: some View {
        VStack(spacing: 16) {
            
            //  Search bar + AR Button
            HStack(spacing: 12) {
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search art...", text: $searchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding()
                .background(AppColors.cardBackground)
                .cornerRadius(20)
                
                // AR button
                NavigationLink {
                    ARDisplayView()
                } label: {
                    Image(systemName: "viewfinder")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(12)
                        .background(
                            LinearGradient(colors: [.purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .clipShape(Circle())
                        .shadow(color: AppColors.cardShadow, radius: 3, x: 0, y: 1)
                }
            }
            .padding(.horizontal)
            
            
            // Top nav bar
            ARTopBar(activeTab: $activeSection)
            
            Divider()
                .background(Color.black.opacity(0.1))
                .padding(.horizontal)
            
            
            // Content Switcher
            ScrollView {
                switch activeSection {
                case "gallery":
                    ARGalleryView(searchQuery: searchQuery)
                        .task {
                            if let user = userVM.currentUser {
                                await wishlistVM.loadWishlist(for: user.id)
                            }
                        }
                case "collection":
                    CollectionView(searchQuery: searchQuery)
                case "wishlist":
                    WishlistView(searchQuery: searchQuery)
                case "map":
                    MapView()
                        .frame(height: 500)
                default:
                    CollectionView()
                }
            }
        }
        .padding(.top)
        .background(AppColors.screenBackground.ignoresSafeArea())
    }
}
