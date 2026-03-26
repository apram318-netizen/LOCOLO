//
//  FilteredPlacesListView.swift
//  Locolo
//
//  Created for Discover page filtered list view
//

import SwiftUI

struct FilteredPlacesListView: View {
    @EnvironmentObject var discoverVM: DiscoverViewModel
    let filterType: FilteredViewType
    @State private var selectedPlace: DiscoverPlace?
    
    var basePlaces: [DiscoverPlace] {
        switch filterType {
        case .mostHyped:
            return discoverVM.mostHyped
        case .weekly:
            return discoverVM.weekly
        case .today:
            return discoverVM.today
        case .all:
            return discoverVM.places
        }
    }
    
    var filteredPlaces: [DiscoverPlace] {
        var result = basePlaces
        
        // Apply category filter
        if let category = discoverVM.selectedCategory {
            result = result.filter { $0.type == category }
        }
        
        // Apply "Near Me" filter (within 1km)
        if discoverVM.showNearMeOnly {
//            result = result.filter { place in
//                guard let distance = place.distance else { return false }
//                return distance <= 1000 // 1km
//            }
        }
        
        // Apply quick filters
        if let quick = discoverVM.quickFilter {
            switch quick {
            case .nearMe: break
//                result = result.filter { $0.distance != nil && $0.distance! <= 1000 }
            case .trending:
                result = result.filter { $0.trending }
            case .new:
                let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
                result = result.filter { $0.createdAt >= weekAgo }
            case .budget:
                result = result.filter { $0.hypes < 300 }
            case .bnb:
                result = result.filter { $0.type.lowercased().contains("bnb") || $0.type.lowercased().contains("bed") }
            }
        }
        
        // Apply sort
        switch discoverVM.sortOption {
        case .popular:
            result.sort(by: { $0.hypes > $1.hypes })
        case .distance: break
//            result.sort(by: { 
//                guard let d1 = $0.distance, let d2 = $1.distance else {
//                    return $0.distance != nil
//                }
//                return d1 < d2
//            })
        case .newest:
            result.sort(by: { $0.createdAt > $1.createdAt })
        case .trending:
            result = result.filter { $0.trending }
                .sorted(by: { $0.hypes > $1.hypes })
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar at top
            FilterBarView()
                .environmentObject(discoverVM)
                .padding(.vertical, 8)
                .background(AppColors.cardBackground)
            
            Divider()
                .background(AppColors.cardShadow)
            
            // Scrollable feed
            ScrollView {
                LazyVStack(spacing: 12) {
                    if filteredPlaces.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundColor(AppColors.secondaryText)
                            Text("No places found")
                                .font(.headline)
                                .foregroundColor(AppColors.primaryText)
                            Text("Try adjusting your filters")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(filteredPlaces) { place in
                            PlaceRowView(place: place)
                                .onTapGesture {
                                    selectedPlace = place
                                }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.screenBackground)
        }
        .navigationTitle(filterType == .all ? "All Places" : sectionTitle)
        .navigationBarTitleDisplayMode(.large)
        .background(AppColors.screenBackground)
        .navigationDestination(item: $selectedPlace) { place in
            PlaceDetailView(place: place)
        }
        .onAppear {
            // Apply preset filters based on filter type
            switch filterType {
            case .mostHyped:
                discoverVM.quickFilter = nil
                discoverVM.sortOption = .popular
            case .weekly:
                discoverVM.quickFilter = nil
                discoverVM.sortOption = .popular
            case .today:
                discoverVM.quickFilter = .new
                discoverVM.sortOption = .newest
            case .all:
                break
            }
        }
    }
    
    private var sectionTitle: String {
        switch filterType {
        case .mostHyped:
            return "Most Hyped"
        case .weekly:
            return "Weekly Winners"
        case .today:
            return "Today's Picks"
        case .all:
            return "All Places"
        }
    }
}

