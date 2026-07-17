//
//  ARGalleryViewModel.swift
//  Locolo
//
//  Backs the AR Search tab: full asset catalogue with text search,
//  category filtering, sorting, and marketplace filters.
//

import SwiftUI
import Foundation

@MainActor
final class ARGalleryViewModel: ObservableObject {

    // MARK: - Sorting

    enum SortOption: String, CaseIterable, Identifiable {
        case popular = "Most Popular"
        case newest = "Newest"
        case oldest = "Oldest"
        case nearest = "Nearest"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .popular: return "flame"
            case .newest: return "clock"
            case .oldest: return "clock.arrow.circlepath"
            case .nearest: return "location"
            }
        }
    }

    // MARK: - Published State

    @Published var artworks: [DigitalAsset] = []
    @Published var searchQuery: String = ""
    @Published var selectedCategory: String = "all"
    @Published var sortOption: SortOption = .popular
    @Published var onlyForSale = false
    @Published var onlyAcceptsOffers = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let repo = DigitalAssetRepository()

    var hasActiveFilters: Bool {
        selectedCategory != "all" || onlyForSale || onlyAcceptsOffers
    }

    // MARK: - Filtering + sorting

    /// Search text + category + marketplace filters + sort, in that order.
    var filteredArtworks: [DigitalAsset] {
        let filtered = artworks.filter { art in
            let matchesSearch =
                searchQuery.isEmpty ||
                (art.name ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                (art.description ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                (art.category ?? "").localizedCaseInsensitiveContains(searchQuery) ||
                (art.displayLocation ?? "").localizedCaseInsensitiveContains(searchQuery)

            let matchesCategory =
                selectedCategory == "all" ||
                (art.category?.lowercased() == selectedCategory.lowercased())

            let matchesSale = !onlyForSale || art.isForSale == true
            let matchesOffers = !onlyAcceptsOffers || art.acceptsOffers == true

            return matchesSearch && matchesCategory && matchesSale && matchesOffers
        }

        switch sortOption {
        case .popular:
            return filtered.sorted { $0.engagementScore > $1.engagementScore }
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .nearest:
            return filtered.sorted {
                ($0.distanceMeters ?? .greatestFiniteMagnitude) <
                ($1.distanceMeters ?? .greatestFiniteMagnitude)
            }
        }
    }

    /// Categories that actually occur in the catalogue, most common first.
    /// Drives the "Browse categories" grid and trending chips.
    var categoryCounts: [(category: String, count: Int)] {
        var counts: [String: Int] = [:]
        for art in artworks {
            let cat = (art.category ?? "other").lowercased()
            counts[cat, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
            .map { (category: $0.key, count: $0.value) }
    }

    /// Names of the most engaged-with assets — the "Trending searches" chips.
    var trendingNames: [String] {
        artworks
            .sorted { $0.engagementScore > $1.engagementScore }
            .prefix(6)
            .compactMap(\.name)
    }

    func resetFilters() {
        selectedCategory = "all"
        onlyForSale = false
        onlyAcceptsOffers = false
        sortOption = .popular
    }

    // MARK: - Loading

    func loadArtworks() async {
        isLoading = artworks.isEmpty
        artworks = await repo.fetchAll()
        errorMessage = nil
        isLoading = false
    }
}
