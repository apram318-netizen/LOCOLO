//
//  PresenceStore.swift
//  Locolo
//
//  Phase D coarse live presence (§5.20). Throttled upserts; nearby list for UI.
//

import Foundation
import Combine
import CoreLocation
import Supabase

struct NearbyExplorer: Identifiable, Hashable {
    var id: UUID { userId }
    let userId: UUID
    let assetId: UUID?
    let updatedAt: Date
    let distanceMeters: Double
}

@MainActor
final class PresenceStore: ObservableObject {
    static let shared = PresenceStore()

    @Published private(set) var nearby: [NearbyExplorer] = []
    @Published var sharingEnabled = true
    @Published private(set) var available = true

    private let client = SupabaseManager.shared.client
    private var me: UUID?
    private var lastUpsert = Date.distantPast

    private init() {
        sharingEnabled = UserDefaults.standard.object(forKey: "ar.presence.share") as? Bool ?? true
    }

    func configure(me: UUID) { self.me = me }

    func reset() {
        me = nil
        nearby = []
        available = true
    }

    func setSharing(_ on: Bool) {
        sharingEnabled = on
        UserDefaults.standard.set(on, forKey: "ar.presence.share")
    }

    private struct Upsert: Encodable {
        let p_lat: Double
        let p_lon: Double
        let p_asset: String?
        let p_visible: Bool
    }

    private struct NearbyParams: Encodable {
        let p_lat: Double
        let p_lon: Double
        let p_radius_m: Double
        let p_limit: Int
    }

    private struct Row: Decodable {
        let user_id: UUID
        let asset_id: UUID?
        let updated_at: Date
        let distance_m: Double
    }

    func heartbeat(near assetId: UUID? = nil) async {
        guard me != nil, sharingEnabled, available else { return }
        guard Date().timeIntervalSince(lastUpsert) > 45 else { return }
        guard let coord = LocationManager.shared.userLocation
                ?? LocationManager.shared.latestStoredLocation else { return }
        lastUpsert = Date()
        do {
            try await client.rpc("upsert_presence", params: Upsert(
                p_lat: coord.latitude, p_lon: coord.longitude,
                p_asset: assetId?.uuidString.lowercased(),
                p_visible: sharingEnabled
            )).execute()
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }

    func refreshNearby(radius: Double = 250) async {
        guard available else { return }
        guard let coord = LocationManager.shared.userLocation
                ?? LocationManager.shared.latestStoredLocation else { return }
        do {
            let rows: [Row] = try await client
                .rpc("get_nearby_explorers", params: NearbyParams(
                    p_lat: coord.latitude, p_lon: coord.longitude,
                    p_radius_m: radius, p_limit: 20))
                .execute()
                .value
            nearby = rows.map {
                NearbyExplorer(userId: $0.user_id, assetId: $0.asset_id,
                               updatedAt: $0.updated_at, distanceMeters: $0.distance_m)
            }
            await CreatorCache.shared.load(nearby.map(\.userId))
            available = true
        } catch {
            if EngagementStore.isMissingSchema(error) { available = false }
        }
    }
}
