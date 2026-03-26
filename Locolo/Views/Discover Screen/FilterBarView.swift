//
//  FilterBarView.swift
//  Locolo
//
//  Created for Discover page filter bar
//

import SwiftUI

struct FilterBarView: View {
    @EnvironmentObject var discoverVM: DiscoverViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Quick filter buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscoverViewModel.QuickFilter.allCases, id: \.self) { filter in
                        QuickFilterButton(
                            filter: filter,
                            isSelected: discoverVM.quickFilter == filter
                        ) {
                            if discoverVM.quickFilter == filter {
                                discoverVM.quickFilter = nil
                            } else {
                                discoverVM.quickFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Category chips and sort
            HStack(spacing: 12) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryChip(
                            name: "All",
                            isSelected: discoverVM.selectedCategory == nil
                        ) {
                            discoverVM.selectedCategory = nil
                        }
                        
                        ForEach(discoverVM.availableCategories, id: \.self) { category in
                            CategoryChip(
                                name: category,
                                isSelected: discoverVM.selectedCategory == category
                            ) {
                                discoverVM.selectedCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Sort picker
                Menu {
                    ForEach(DiscoverViewModel.SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            discoverVM.sortOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if discoverVM.sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                        Text(discoverVM.sortOption.rawValue)
                            .font(.subheadline)
                    }
                    .foregroundColor(AppColors.primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.categoryBadge)
                    .cornerRadius(16)
                }
            }
            
            // Near Me toggle
            Toggle(isOn: $discoverVM.showNearMeOnly) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text("Near Me (1km)")
                        .font(.subheadline)
                }
                .foregroundColor(AppColors.primaryText)
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.orange))
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(AppColors.cardBackground)
    }
}

struct QuickFilterButton: View {
    let filter: DiscoverViewModel.QuickFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.caption)
                Text(filter.rawValue)
                    .font(.subheadline)
            }
            .foregroundColor(isSelected ? .white : AppColors.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Group {
                    if isSelected {
                        AppColors.trendingBadge
                    } else {
                        AppColors.categoryBadge
                    }
                }
            )
            .cornerRadius(16)
        }
    }
    
    private var iconName: String {
        switch filter {
        case .nearMe:
            return "location.fill"
        case .trending:
            return "flame.fill"
        case .new:
            return "sparkles"
        case .budget:
            return "dollarsign.circle.fill"
        case .bnb:
            return "bed.double.fill"
        }
    }
}

struct CategoryChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.subheadline)
                .foregroundColor(isSelected ? .white : AppColors.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? AppColors.blueCyanGradient
                        : LinearGradient(colors: [AppColors.categoryBadge], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(16)
        }
    }
}

