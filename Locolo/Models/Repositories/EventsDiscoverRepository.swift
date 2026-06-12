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

    // MARK: - ATTENDANCE FLOW

    // Internal decode model for the attendee + user join
    private struct AttendeeRow: Codable {
        let userId: UUID
        let status: String
        let user: AttendeeUserRow

        struct AttendeeUserRow: Codable {
            let userId: UUID
            let username: String
            let avatarUrl: String?

            enum CodingKeys: String, CodingKey {
                case userId    = "user_id"
                case username
                case avatarUrl = "avatar_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case status
            case user
        }
    }

    // Upsert payload — Codable so Supabase can encode it cleanly
    private struct AttendeeUpsertPayload: Codable {
        let eventId: UUID
        let userId: UUID
        let status: String

        enum CodingKeys: String, CodingKey {
            case eventId = "event_id"
            case userId  = "user_id"
            case status
        }
    }

    // MARK: FUNCTION: fetchAttendees
    /// Returns a preview list (top N) for avatar stacks on event cards and detail views.
    func fetchAttendees(eventId: UUID, limit: Int = 5) async throws -> [AttendeePreview] {
        let rows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("user_id, status, user:users(user_id, username, avatar_url)")
            .eq("event_id", value: eventId.uuidString)
            .limit(limit)
            .execute()
            .value

        return rows.map { row in
            AttendeePreview(
                id: row.user.userId,
                username: row.user.username,
                avatarUrl: row.user.avatarUrl,
                status: AttendanceStatus(rawValue: row.status) ?? .going
            )
        }
    }

    // MARK: FUNCTION: fetchAllAttendees
    /// Paginated fetch for the full attendees list sheet, filtered by status.
    func fetchAllAttendees(eventId: UUID, status: AttendanceStatus, from: Int, limit: Int = 20) async throws -> [AttendeePreview] {
        let rows: [AttendeeRow] = try await client
            .from("event_attendees")
            .select("user_id, status, user:users(user_id, username, avatar_url)")
            .eq("event_id", value: eventId.uuidString)
            .eq("status", value: status.rawValue)
            .range(from: from, to: from + limit - 1)
            .execute()
            .value

        return rows.map { row in
            AttendeePreview(
                id: row.user.userId,
                username: row.user.username,
                avatarUrl: row.user.avatarUrl,
                status: AttendanceStatus(rawValue: row.status) ?? .going
            )
        }
    }

    // MARK: FUNCTION: fetchMyStatus
    /// Returns the current user's attendance status for an event, or nil if not attending.
    func fetchMyStatus(eventId: UUID, userId: UUID) async throws -> AttendanceStatus? {
        struct StatusRow: Codable { let status: String }
        let rows: [StatusRow] = try await client
            .from("event_attendees")
            .select("status")
            .eq("event_id", value: eventId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value

        guard let raw = rows.first?.status else { return nil }
        return AttendanceStatus(rawValue: raw)
    }

    // MARK: FUNCTION: fetchAttendeeCounts
    /// Returns going + interested counts. Fetches all status rows and counts client-side.
    func fetchAttendeeCounts(eventId: UUID) async throws -> (going: Int, interested: Int) {
        struct Row: Codable { let status: String }
        let rows: [Row] = try await client
            .from("event_attendees")
            .select("status")
            .eq("event_id", value: eventId.uuidString)
            .execute()
            .value

        let going      = rows.filter { $0.status == AttendanceStatus.going.rawValue }.count
        let interested = rows.filter { $0.status == AttendanceStatus.interested.rawValue }.count
        return (going, interested)
    }

    // MARK: FUNCTION: toggleAttendance
    /// Upserts if new/different status, deletes if tapping same status again (toggle off).
    /// Returns the new status, or nil if attendance was removed.
    func toggleAttendance(
        eventId: UUID,
        userId: UUID,
        newStatus: AttendanceStatus,
        currentStatus: AttendanceStatus?
    ) async throws -> AttendanceStatus? {
        if currentStatus == newStatus {
            // Same button tapped again → remove
            try await client
                .from("event_attendees")
                .delete()
                .eq("event_id", value: eventId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
            return nil
        } else {
            // New or changed status → upsert
            let payload = AttendeeUpsertPayload(
                eventId: eventId,
                userId: userId,
                status: newStatus.rawValue
            )
            try await client
                .from("event_attendees")
                .upsert(payload)
                .execute()
            return newStatus
        }
    }
}

