//
//  DiscoverRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//
//  okay this file is the “discover brain”
//  basically anything the user browses on the Discover tab
//  places, events, activities
//  is coming directly from here.
//
//  this is all Supabase. no firebase here.
//  no caching except a tiny in-memory category cache.
//  everything is shaped into lightweight structs
//  that the UI uses to show cards.


import Foundation

class DiscoverRepository {

    private let client = SupabaseManager.shared.client

    // might use this later to skip re-fetching categories if needed
    private var categoryCache: [UUID: String] = [:]
    
    // discover is always scoped to a loop
    // Computed property to always read fresh from UserDefaults
    var loopId: String? {
        UserDefaults.standard.string(forKey: "selectedLoopId")
    }


    // MARK: FUNCTION: fetchDiscoverPlaces
    /// - Description: this is the "main discover feed"
    /// fetches places from supabase and joins the category table.
    /// Filters places by the user's active loop_id to only show relevant places.
    ///
    /// flow:
    ///  grab places from table `places` filtered by loop_id
    ///   join --> categories(name)
    ///  convert score (0–1) to hype count (0–1000)
    ///  fallback category -->"General"
    /// ...and finally fallback img --> a random unsplash default
    ///
    /// - Returns: [DiscoverPlace] → clean lightweight struct ready for UI
    func fetchDiscoverPlaces() async throws -> [DiscoverPlace] {
        // Get active loop ID from UserDefaults
        guard let loopId = loopId else {
            print(" No selected loop ID found - returning empty places")
            return []
        }
        
        // Filter at database level - only fetch places for this loop
        // Explicitly select place_id to ensure it's included in the response
        let response: [PlaceWithCategory]
        do {
            response = try await client
                .from("places")
                .select("place_id, name, description, place_image_url, category_id, trending, created_at, categories(name)")
                .eq("loop_id", value: loopId)
                .execute()
                .value
            
            // Debug: Log successful decode
            if let first = response.first {
                print("✅ Successfully decoded \(response.count) places")
                print("📋 First place - place_id: \(String(describing: first.place_id)), name: \(first.name)")
            }
        } catch {
            print("❌ [FETCH_DISCOVER_PLACES] file:\(#fileID) line:\(#line) func:\(#function) \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                    // Try to print available keys if possible
                    if let underlyingError = context.underlyingError {
                        print("   Underlying error: \(underlyingError)")
                    }
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            throw error
        }

        return response.compactMap { p -> DiscoverPlace? in
            // Skip if place_id is missing (shouldn't happen, but handle gracefully)
            guard let placeId = p.place_id else {
                print("⚠️ Skipping place with missing place_id: \(p.name)")
                return nil
            }
            
            return DiscoverPlace(
                id: placeId,
                name: p.name,
                hypes: Int((p.score ?? 0.5) * 1000),
                type: p.categories?.name ?? "General",
                image: p.place_image_url
                    ?? "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=200&h=150&fit=crop",
                trending: p.trending ?? false,
                description: p.description ?? "Discover this amazing place",
                createdAt: p.created_at ?? Date()
            )
        }
    }



    // MARK: FUNCTION: searchEvents
    /// - Description: search bar → events.
    /// grabs events inside the current loop and filters by name.
    /// formats date + time nicely for the UI because otherwise it looks ugly.
    ///
    /// NOTE: some fields are fake for now like attendees & hype counts → until proper event algo exists.
    func searchEvents(query: String) async throws -> [EventItem] {

        guard let loopId else {
            print(" No selected loop ID found")
            return []
        }

        let dbEvents: [Event] = try await client
            .from("events")
            .select()
            .eq("loop_id", value: loopId)
            .ilike("name", pattern: "%\(query)%")
            .limit(10)
            .execute()
            .value

        // simple date formatting for UI
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        // mapping the DB model → UI card model
        return dbEvents.enumerated().map { index, event in
            // Use startAt instead of eventDateTime (which no longer exists in DB)
            let eventDate = event.startAt ?? event.endAt ?? Date()
            
            return EventItem(
                id: event.id,
                name: event.name,
                date: dateFormatter.string(from: eventDate),
                time: timeFormatter.string(from: eventDate),
                location: "TBD",
                price: "Check details",
                attendees: Int.random(in: 100...2500),
                hypes: Int.random(in: 50...600),
                image: event.eventImageUrl
                    ?? "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=400&h=200&fit=crop",
                ticketUrl: "https://tickets.example.com",
                category: event.categoryId?.uuidString.prefix(10).description ?? "General",
                featured: index % 2 == 0,
                description: event.description ?? "No description available"
            )
        }
    }



    // MARK: FUNCTION: searchActivities
    /// - Description: same vibe as events, but for activities.
    /// just pulls “activities” rows for this loop + filters on name.
    ///
    /// some fields are placeholders until activity metadata is fully built.
    func searchActivities(query: String) async throws -> [ActivityItem] {

        guard let loopId else {
            print(" No selected loop ID")
            return []
        }

        let response: [Activity] = try await client
            .from("activities")
            .select()
            .eq("loop_id", value: loopId)
            .ilike("name", pattern: "%\(query)%")
            .limit(10)
            .execute()
            .value

        return response.map { a in
            ActivityItem(
                id: a.id,
                name: a.name,
                type: a.categoryId?.uuidString.prefix(10).description ?? "General",
                duration: "Varies",
                price: "Check details",
                description: a.description ?? "No description available",
                rating: 4.5,
                participants: Int.random(in: 100...2000),
                image: a.activityImageUrl
                    ?? "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=200&h=150&fit=crop",
                hypes: Int.random(in: 50...500)
            )
        }
    }



    // MARK: FUNCTION: searchDiscoverPlaces
    /// - Description: discover → places search bar.
    /// identical idea to fetchDiscoverPlaces() but with a name filter.
    ///
    /// still applies:
    ///  - hype score scaling
    ///  - category fallback
    ///  - image fallback
    func searchDiscoverPlaces(query: String) async throws -> [DiscoverPlace] {

        guard let loopId else {
            print(" No selected loop ID")
            return []
        }

        let response: [PlaceWithCategory]
        do {
            response = try await client
                .from("places")
                .select("place_id, name, description, place_image_url, category_id, trending, created_at, categories(name)")
                .eq("loop_id", value: loopId)
                .ilike("name", pattern: "%\(query)%")
                .limit(10)
                .execute()
                .value
            
            // Debug: Log successful decode
            if let first = response.first {
                print("✅ Successfully decoded \(response.count) places from search")
                print("📋 First place - place_id: \(String(describing: first.place_id)), name: \(first.name)")
            }
        } catch {
            print("❌ [SEARCH_DISCOVER_PLACES] file:\(#fileID) line:\(#line) func:\(#function) \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("   Missing key: \(key.stringValue)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                    // Try to print available keys if possible
                    if let underlyingError = context.underlyingError {
                        print("   Underlying error: \(underlyingError)")
                    }
                case .typeMismatch(let type, let context):
                    print("   Type mismatch: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("   Value not found: \(type)")
                    print("   Context: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context.debugDescription)")
                    print("   Coding path: \(context.codingPath)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            throw error
        }

        return response.compactMap { p -> DiscoverPlace? in
            // Skip if place_id is missing
            guard let placeId = p.place_id else {
                print("⚠️ Skipping place with missing place_id: \(p.name)")
                return nil
            }
            
            return DiscoverPlace(
                id: placeId,
                name: p.name,
                hypes: Int((p.score ?? 0.5) * 1000),
                type: p.categories?.name ?? "General",
                image: p.place_image_url
                    ?? "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=200&h=150&fit=crop",
                trending: p.trending ?? false,
                description: p.description ?? "Discover this amazing place",
                createdAt: p.created_at ?? Date()
            )
        }
    }
    
    // MARK: FUNCTION: fetchCategories
    /// - Description: Fetches available categories for the current loop
    /// - Returns: Array of unique category names
    func fetchCategories() async throws -> [String] {
        guard let loopId = loopId else {
            return []
        }
        
        // Use minimal struct that only needs categories (not name or other fields)
        let response: [PlaceCategoryOnly] = try await client
            .from("places")
            .select("categories(name)")
            .eq("loop_id", value: loopId)
            .execute()
            .value
        
        let categories = response.compactMap { $0.categories?.name }
        return Array(Set(categories)).sorted()
    }

}


// MARK: - Helper for categories-only queries
/// Minimal struct for queries that only need category information
struct PlaceCategoryOnly: Codable {
    let categories: CategoryName?
    
    struct CategoryName: Codable {
        let name: String
    }
}

// MARK: - Helper for nested category join
/// Supabase returns `categories(name)` as:
///    { categories: { name: "Food" } }
/// so this struct shapes that exactly.
struct PlaceWithCategory: Codable {
    let place_id: UUID?  // Made optional to handle cases where it might not be returned
    let name: String
    let description: String?
    let place_image_url: String?
    let category_id: UUID?
    let score: Double?
    let categories: CategoryName?
    let created_at: Date?  // Made optional - might be null in some rows
    let trending: Bool?

    // Explicit CodingKeys to ensure proper mapping
    enum CodingKeys: String, CodingKey {
        case place_id
        case name
        case description
        case place_image_url
        case category_id
        case score
        case categories
        case created_at
        case trending
    }

    struct CategoryName: Codable {
        let name: String
    }
}
