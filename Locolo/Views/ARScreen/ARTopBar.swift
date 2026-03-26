//
//  ARTopBar.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/9/2025.
//

import SwiftUI

struct ARTopBar: View {
    @Binding var activeTab: String
    
    var body: some View {
        // MARK: - Tab Container
        // Holds all the tab buttons and gives them a shared style.
        HStack(spacing: 8) {
            
            // MARK: Gallery Tab
            TabButton(
                title: "Gallery",
                icon: "square.grid.2x2",
                isActive: activeTab == "gallery",
                colors: [.purple, .pink]
            ) { activeTab = "gallery" }
            
            // MARK: Collection Tab
            TabButton(
                title: "Collection",
                icon: "bag",
                isActive: activeTab == "collection",
                colors: [.blue, .cyan]
            ) { activeTab = "collection" }
            
            // MARK: Wishlist Tab
            TabButton(
                title: "Wishlist",
                icon: "heart",
                isActive: activeTab == "wishlist",
                colors: [.green, .teal]
            ) { activeTab = "wishlist" }
            
            // MARK: Map Tab
            TabButton(
                title: "Map",
                icon: "map",
                isActive: activeTab == "map",
                colors: [.orange, .red]
            ) { activeTab = "map" }
        }
        .padding(6)
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: AppColors.cardShadow, radius: 2, x: 0, y: 1)
        .padding(.horizontal)
    }
}

//
// MARK: - Single Tab Button
// A reusable button that shows an icon and label.
// It highlights with a gradient when active.
//

struct TabButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let colors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isActive {
                        LinearGradient(colors: colors,
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    } else {
                        AppColors.cardBackground
                    }
                }
            )
            .foregroundColor(isActive ? .white : AppColors.secondaryText)
            .cornerRadius(16)
            .shadow(
                color: isActive ? AppColors.cardShadow : .clear,
                radius: 2, x: 0, y: 1
            )
        }
    }
}
