//
//  EventsStore.swift
//  Locolo
//
//  Phase D AR events / meetups (§5.20).
//

import Foundation
import Combine
import Supabase

struct AREvent: Identifiable, Hashable {
    let id: UUID
    let hostId: UUID
    var title: String
    var detail: String?
    let lat: Double
    let lon: Double
    var placeName: String?
    let startsAt: Date
    var endsAt: Date?
    var rsvpCount: Int
    var myStatus: String?
}

@MainActor
final class EventsStore: ObservableObject {
    static let shared = EventsStore()

    @Published private(set) var upcoming: [AREvent] = []
    @Published private(set) var available = true
    @Published private(set) var hasLoaded = false

    private let client = SupabaseManager.shared.client
    private var me: UUID?

    private init() {}

    func configure(me: UUID) { self.me = me }

    func reset() {
        me = nil
        upcoming = []
        available = true
        hasLoaded = false
    }

    private struct EventRow: Decodable {
        let event_id: UUID
        let host_id: UUID
        let title: String
        let detail: String?
        let lat: Double
        let lon: Double
        let place_name: String?
        let starts_at: Date
        let ends_at: Date?
    }

    func refresh() async {
        do {
            let rows: [EventRow] = try await client
                .from("ar_events")
                .select("*")
                .gte("starts_at", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600)))
                .order("starts_at", ascending: true)
                .limit(40)
                .execute()
                .value
            available = true
            var events = rows.map {
                AREvent(id: $0.event_id, hostId: $0.host_id, title: $0.title,
                        detail: $0.detail, lat: $0.lat, lon: $0.lon,
                        placeName: $0.place_name, startsAt: $0.starts_at,
                        endsAt: $0.ends_at, rsvpCount: 0, myStatus: nil)
            }
            await attachRSVPs(&events)
            upcoming = events
            await CreatorCache.shared.load(events.map(\.hostId))
        } catch {
            if EngagementStore.isMissingSchema(error) {
                available = false
                upcoming = []
            }
        }
        hasLoaded = true
    }

    private struct RSVPRow: Decodable {
        let event_id: UUID
        let user_id: UUID
        let status: String
    }

    private func attachRSVPs(_ events: inout [AREvent]) async {
        guard !events.isEmpty else { return }
        do {
            let rows: [RSVPRow] = try await client
                .from("ar_event_rsvps")
                .select("event_id, user_id, status")
                .in("event_id", values: events.map { $0.id.uuidString })
                .neq("status", value: "cancelled")
                .execute()
                .value
            let grouped = Dictionary(grouping: rows, by: \.event_id)
            for i in events.indices {
                let list = grouped[events[i].id] ?? []
                events[i].rsvpCount = list.count
                if let me {
                    events[i].myStatus = list.first(where: { $0.user_id == me })?.status
                }
            }
        } catch { /* optional */ }
    }

    func create(title: String, detail: String?, lat: Double, lon: Double,
                placeName: String?, startsAt: Date) async throws -> AREvent {
        guard let me else { throw NSError(domain: "Events", code: -1) }
        struct Insert: Encodable {
            let host_id: UUID
            let title: String
            let detail: String?
            let lat: Double
            let lon: Double
            let place_name: String?
            let starts_at: Date
        }
        let row: EventRow = try await client
            .from("ar_events")
            .insert(Insert(host_id: me, title: title, detail: detail, lat: lat, lon: lon,
                           place_name: placeName, starts_at: startsAt))
            .select("*")
            .single()
            .execute()
            .value
        let event = AREvent(id: row.event_id, hostId: row.host_id, title: row.title,
                            detail: row.detail, lat: row.lat, lon: row.lon,
                            placeName: row.place_name, startsAt: row.starts_at,
                            endsAt: row.ends_at, rsvpCount: 1, myStatus: "going")
        _ = try? await rsvp(eventId: event.id, status: "going")
        upcoming.insert(event, at: 0)
        return event
    }

    func rsvp(eventId: UUID, status: String) async throws {
        guard let me else { return }
        struct Upsert: Encodable {
            let event_id: UUID
            let user_id: UUID
            let status: String
        }
        try await client.from("ar_event_rsvps")
            .upsert(Upsert(event_id: eventId, user_id: me, status: status))
            .execute()
        if let idx = upcoming.firstIndex(where: { $0.id == eventId }) {
            upcoming[idx].myStatus = status
        }
    }
}
