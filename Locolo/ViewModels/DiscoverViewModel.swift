//
//  DiscoverViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//

import Foundation

/// - Description: Handles the Discover tab and  pulls places for exploration snd  organizes them into trending, weekly, and today sections for the UI.
@MainActor
class DiscoverViewModel: ObservableObject {
    // MARK: - Published State
    @Published var places: [DiscoverPlace] = []     // list of fetched  places
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let repository = DiscoverRepository()
    
    
    
    @Published var searchResultsPlaces: [DiscoverPlace] = []
    @Published var searchResultsEvents: [EventItem] = []
    @Published var searchResultsActivities: [ActivityItem] = []
    
    @Published var isSearching = false
    @Published var searchQuery = ""
    
    // MARK: - Filter State
    @Published var selectedCategory: String?
    @Published var sortOption: SortOption = .popular
    @Published var showNearMeOnly = false
    @Published var quickFilter: QuickFilter?
    @Published var availableCategories: [String] = []
    
    enum SortOption: String, CaseIterable {
        case popular = "Popular"
        case distance = "Distance"
        case newest = "Newest"
        case trending = "Trending"
    }
    
    enum QuickFilter: String, CaseIterable {
        case nearMe = "Near Me"
        case trending = "Trending"
        case new = "New"
        case budget = "Budget"
        case bnb = "BnB"
    }
    
    // MARK: FUNCTION: loadPlaces
    /// - Description: Fetches discoverable places from the repository.
    /// Currently grabs everything, then filters locally — later we can optimize this
    /// by fetching only relevant data and adding proper filters or scoring.
    func loadPlaces() async {
        isLoading = true
        errorMessage = nil
        
        do {
            places = try await repository.fetchDiscoverPlaces()
            // Also fetch available categories for filters
            availableCategories = try await repository.fetchCategories()
        } catch {
            errorMessage = "Failed to load places: \(error.localizedDescription)"
            print("❌ [DISCOVER_LOAD] file:\(#fileID) line:\(#line) func:\(#function) \(error)")
        }
        
        isLoading = false
    }
    
    
    // MARK: - Categorized Sections
    // These computed properties are mainly for UI compatibility — we can refactor them later
    // once we have better scoring and filtering on the backend side.
    
    // Discussion:
    //Things that still need improvement here: expand it if you want to. This helps with reccomendations better and later AI integration and if I I have enough energy to implement RAG
    /*
     - need to add more  criteria for trending, not just createdAt or hypes.
     - Iam planning  a “scoring algorithm” that ranks places by multiple things like hypes, recency,
     user visits, and possibly loop activity, and views and I will probably use pg vector for the same.
     -  Avoid fetching all places every time. Instead, request smaller chunks (maybe top 50)
     from Supabase using filters, pagination, or relevance queries.
     -  Later, integrate user location and interests to personalize discover results.
     -  If time allows, add caching and additional appending refresh functionality instead of reloading the full dataset.
     - If planning rag the try to wire it upto supabase for the vector database integration. I dont think I will before the assignment.
     */
    
    
    
    
    
    // MARK: Section: Most Hyped
    /// - Description: Returns top trending places sorted by recency.
    var mostHyped: [DiscoverPlace] {
        places
            .filter { $0.trending }
            .sorted(by: { $0.createdAt > $1.createdAt })
            .prefix(10)
            .map { $0 }
    }
    
    
    // MARK: Section: Weekly Highlights
    /// - Description: Places that aren’t trending but still performing well (high hypes count).
    var weekly: [DiscoverPlace] {
        places
            .filter { !$0.trending && $0.hypes > 200 }
            .prefix(5)
            .map { $0 }
    }
    
    
    // MARK: Section: Today’s Picks
    /// - Description: Smaller, newer, or niche places with moderate hype.
    var today: [DiscoverPlace] {
        places
            .filter { $0.hypes <= 200 }
            .prefix(5)
            .map { $0 }
    }
    
    
    
    // MARK: - SEARCH EVENTS
    func searchEvents(_ query: String) {
        guard !query.isEmpty else {
            searchResultsEvents = []
            return
        }
        
        Task {
            do {
                let results = try await repository.searchEvents(query: query)
                self.searchResultsEvents = results
            } catch {
                print(" Event search error:", error)
            }
        }
    }
    
    
    // MARK: - SEARCH ACTIVITIES
    func searchActivities(_ query: String) {
        guard !query.isEmpty else {
            searchResultsActivities = []
            return
        }
        
        Task {
            do {
                let results = try await repository.searchActivities(query: query)
                self.searchResultsActivities = results
            } catch {
                print(" Activity search error:", error)
            }
        }
    }
    
    
    // MARK: - SEARCH PLACES
    func searchPlaces(_ query: String) {
        guard !query.isEmpty else {
            searchResultsPlaces = []
            return
        }
        
        Task {
            do {
                let results = try await repository.searchDiscoverPlaces(query: query)
                self.searchResultsPlaces = results
            } catch {
                print(" Place search error:", error)
            }
        }
    }
    
}
