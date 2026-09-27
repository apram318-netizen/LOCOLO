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

    /// Semantic matches from the pgvector pipeline (WS5.3). Empty when the
    /// embed-query function isn't deployed / errors — keyword search still works.
    @Published var semanticResults: [DigitalAsset] = []
    @Published var isDeepSearching = false

    private let repo = DigitalAssetRepository()
    private let client = SupabaseManager.shared.client

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

    // MARK: - Deep semantic search (WS5.3)

    private struct EmbedResponse: Decodable { let embedding: [Double] }

    private struct SemanticParams: Encodable {
        let p_user: String
        let p_lat: Double
        let p_lon: Double
        let p_radius_meters: Double
        let p_query_embedding: String
        let p_limit: Int
    }

    /// Embed the query via the embed-query edge function, then rank with
    /// get_recommended_assets. Degrades silently to keyword-only search when
    /// the function isn't deployed, the user has no location, or anything fails.
    func deepSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3 else {
            semanticResults = []
            return
        }
        guard
            let idString = SupabaseManager.shared.currentUserId,
            let coord = LocationManager.shared.userLocation ?? LocationManager.shared.latestStoredLocation
        else { return }

        isDeepSearching = true
        defer { isDeepSearching = false }

        do {
            // 1) Embed the query text.
            var request = URLRequest(url: URL(string: "\(Secrets.supabaseURL)/functions/v1/embed-query")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(["q": query])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                semanticResults = []   // function not deployed yet — keyword only
                return
            }
            let embedding = try JSONDecoder().decode(EmbedResponse.self, from: data).embedding
            let vectorLiteral = "[" + embedding.map { String($0) }.joined(separator: ",") + "]"

            // 2) Rank semantically (same 41-column shape as the nearby RPC).
            let results: [DigitalAsset] = try await client
                .rpc("get_recommended_assets", params: SemanticParams(
                    p_user: idString,
                    p_lat: coord.latitude,
                    p_lon: coord.longitude,
                    p_radius_meters: 50_000,
                    p_query_embedding: vectorLiteral,
                    p_limit: 20
                ))
                .execute()
                .value

            semanticResults = results
        } catch {
            semanticResults = []
            print("Deep search unavailable:", error.localizedDescription)
        }
    }
}
