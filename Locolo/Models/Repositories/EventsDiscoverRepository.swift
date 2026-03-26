//
//  EventsDiscoverRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//

import Foundation

class EventsDiscoverRepository {
    private let client = SupabaseManager.shared.client
    
    // MARK: FUNCTION: fetchEvents
    /// - Description: Fetches events from Supabase and converts them into lightweight `EventItem`s for the UI.
    /// Adds some filler data (like price, location, and hype counts) since the DB doesn't store everything yet.
    /// Filters events by the user's active loop_id to only show relevant events.
    ///
    /// - Returns: A list of ready-to-display `EventItem` objects for the Discover or Events screen
    func fetchEvents() async throws -> [EventItem] {
        // Get active loop ID from UserDefaults (same pattern as DiscoverRepository)
        guard let loopIdString = UserDefaults.standard.string(forKey: "selectedLoopId") else {
            print(" No selected loop ID found - returning empty events")
            return []
        }
        
        // Filter at database level - only fetch events for this loop
        // Explicitly select fields to match Event struct and avoid decoding errors
        let response: [Event] = try await client
            .from("events")
            .select("event_id, place_id, loop_id, posted_by, name, description, category_id, event_image_url, trailer_media_url, created_at, price, is_free, max_attendees, event_type, start_at, end_at, timezone, official_url, official_url_label, location_mode, online_url, visibility, status, currency")
            .eq("loop_id", value: loopIdString)
            .execute()
            .value
        
        // Convert Event (database) to EventItem (view)
        return response.enumerated().map { (index, event) in
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            
            // Use startAt instead of eventDateTime (which no longer exists in DB)
            let eventDate = event.startAt ?? event.endAt ?? Date()
            
            return EventItem(
                id: event.id,
                name: event.name,
                date: dateFormatter.string(from: eventDate),
                time: timeFormatter.string(from: eventDate),
                location: "TBD", // Not in database, use default
                price: "Check details", // Not in database, use default
                attendees: Int.random(in: 100...2500),
                hypes: Int.random(in: 50...600),
                image: event.eventImageUrl ?? "https://images.unsplash.com/photo-1492684223066-81342ee5ff30?w=400&h=200&fit=crop",
                ticketUrl: "https://tickets.example.com",
                category: event.categoryId?.uuidString.prefix(10).description ?? "General",
                featured: index % 2 == 0, // Alternate featured status
                description: event.description ?? "No description available"
            )
        }
    }
    
    // MARK: ========================================
    // MARK: EVENT POSTING FLOW - ADDED RECENTLY
    // MARK: ========================================
    // Function to create a new event in the database
    
    // MARK: FUNCTION: createEvent
    /// - Description: Creates a new event in Supabase and returns the created event.
    /// Used when a user creates a new event as part of the post creation flow.
    ///
    /// - Parameter event: The PostEvent object containing event details
    /// - Returns: The created Event with its generated ID
    func createEvent(_ event: PostEvent) async throws -> Event {
        do {
            // Insert the event into Supabase
            // Explicitly select only fields that exist in the database to avoid event_datetime issues
            let response: [Event] = try await client
                .from("events")
                .insert(event)
                .select("event_id, place_id, loop_id, posted_by, name, description, category_id, event_image_url, trailer_media_url, created_at, price, is_free, max_attendees, event_type, start_at, end_at, timezone, official_url, official_url_label, location_mode, online_url, visibility, status, currency")
                .execute()
                .value
            
            guard let createdEvent = response.first else {
                throw NSError(domain: "EventCreation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create event - no response"])
            }
            
            print(" [EVENT POSTING] Created event: \(createdEvent.name) with ID: \(createdEvent.id)")
            return createdEvent
        } catch {
            print(" [EVENT POSTING] Failed to create event: \(error)")
            throw error
        }
    }
    
    // MARK: FUNCTION: fetchRawEvents
    /// - Description: Fetches raw Event objects (not EventItems) for the active loop.
    /// Used in the post creation flow to populate the event picker.
    ///
    /// - Returns: A list of Event objects for the active loop
    func fetchRawEvents() async throws -> [Event] {
        guard let loopIdString = UserDefaults.standard.string(forKey: "selectedLoopId") else {
            print(" [EVENT POSTING] No selected loop ID found - returning empty events")
            return []
        }
        
        // Explicitly select fields to match Event struct and avoid decoding errors
        let response: [Event] = try await client
            .from("events")
            .select("event_id, place_id, loop_id, posted_by, name, description, category_id, event_image_url, trailer_media_url, created_at, price, is_free, max_attendees, event_type, start_at, end_at, timezone, official_url, official_url_label, location_mode, online_url, visibility, status, currency")
            .eq("loop_id", value: loopIdString)
            .execute()
            .value
        
        return response
    }
    
    // MARK: FUNCTION: fetchEventById
    /// - Description: Fetches a single event by its ID.
    /// Used to fetch event data for event posts in the feed.
    ///
    /// - Parameter eventId: The UUID of the event to fetch
    /// - Returns: The Event object if found, nil otherwise
    func fetchEventById(_ eventId: UUID) async throws -> Event? {
        let response: [Event] = try await client
            .from("events")
            .select("event_id, place_id, loop_id, posted_by, name, description, category_id, event_image_url, trailer_media_url, created_at, price, is_free, max_attendees, event_type, start_at, end_at, timezone, official_url, official_url_label, location_mode, online_url, visibility, status, currency")
            .eq("event_id", value: eventId.uuidString)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
}

