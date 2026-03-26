//
//  PlacesTab.swift
//  Locolo
//
//  Created by Apramjot Singh on 1/10/2025.
//

import SwiftUI
import MapKit

// MARK: - Place Navigation Wrapper
// Wrapper struct to make Place Hashable for navigation
struct PlaceNavigationItem: Identifiable, Hashable {
    let id: UUID
    let place: Place
    
    init(place: Place) {
        self.place = place
        self.id = place.id
    }
    
    static func == (lhs: PlaceNavigationItem, rhs: PlaceNavigationItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PlacesTab: View {
    let places: [Place]
    @Binding var listMode: Bool
    
    // MARK: Navigation State
    // State for presenting place detail view
    @State private var selectedPlace: PlaceNavigationItem?

    var body: some View {
        VStack {
            // MARK: Header Section
            // Header
            HStack {
                Text("Explored Places")
                    .font(.headline)
                Spacer()
                Button(action: { listMode = true }) {
                    Image(systemName: "list.bullet")
                }
            }
            .padding(.horizontal, 6) //  subtle padding for the header
            
            // MARK: Content Section
            // Content
            if listMode {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(places) { place in
                        Button {
                            selectedPlace = PlaceNavigationItem(place: place)
                        } label: {
                            HStack(spacing: 12) {
                                AsyncImage(url: URL(string: place.placeImageUrl ?? "")) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if let desc = place.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.gray)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6) //  very light side padding per row
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        // MARK: Place Detail Navigation
        // Presents place overview screen when a place is tapped using navigation
        .navigationDestination(item: $selectedPlace) { item in
            PlaceOverviewScreen(place: item.place)
        }
    }
}

// Commented the maps functionality out for now for time restrains
