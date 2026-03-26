//
//  PlaceRowView.swift
//  Locolo
//
//  Created for Discover page place row in filtered list
//

import SwiftUI

struct PlaceRowView: View {
    let place: DiscoverPlace
    
    var body: some View {
        HStack(spacing: 12) {
            // Image
            AsyncImage(url: URL(string: place.image)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                AppColors.secondaryText.opacity(0.3)
            }
            .frame(width: 80, height: 80)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.cardShadow, lineWidth: 1)
            )
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(place.name)
                        .font(.headline)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if place.trending {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundColor(Color.orange)
                    }
                }
                
                HStack(spacing: 8) {
                    Text(place.type)
                        .font(.caption)
                        .foregroundColor(AppColors.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.categoryBadge)
                        .cornerRadius(8)
                    
                    Label("\(place.hypes)", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    
//                    if let distance = place.distance {
//                        Label(formatDistance(distance), systemImage: "location.fill")
//                            .font(.caption)
//                            .foregroundColor(AppColors.secondaryText)
//                    }
                }
                
//                if let visitCount = place.visitCount, visitCount > 0 {
//                    HStack(spacing: 4) {
//                        Image(systemName: "person.2.fill")
//                            .font(.caption2)
//                        Text("\(visitCount) visits")
//                            .font(.caption2)
//                    }
//                    .foregroundColor(AppColors.secondaryText)
//                }
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 1)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 100 {
            return "\(Int(meters))m"
        } else if meters < 1000 {
            return String(format: "%.0fm", meters)
        } else if meters < 20000 {
            return String(format: "%.1fkm", meters / 1000)
        } else {
            return String(format: "%.1fmi", meters / 1609.34)
        }
    }
}

