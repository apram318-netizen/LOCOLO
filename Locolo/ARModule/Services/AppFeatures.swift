//
//  AppFeatures.swift
//  Locolo
//
//  Server-controlled feature switches read from `app_config` (readable by any
//  signed-in user). A missing row or a failed read means "off", so a feature
//  never appears by accident. The database enforces the same switches
//  (docs/migrations/2026_v3_release_gates.sql); this only hides the UI.
//

import Foundation
import Combine
import Supabase

@MainActor
final class AppFeatures: ObservableObject {
    static let shared = AppFeatures()

    /// Listings, buying, auctions, wallets and payouts. Off for launch.
    @Published private(set) var marketplaceEnabled = false

    private let client = SupabaseManager.shared.client

    private init() {}

    private struct Row: Decodable {
        let key: String
        let value: Bool?
    }

    func refresh() async {
        do {
            let rows: [Row] = try await client
                .from("app_config")
                .select("key, value")
                .in("key", values: ["marketplace_enabled"])
                .execute()
                .value
            let flags = Dictionary(rows.map { ($0.key, $0.value ?? false) }, uniquingKeysWith: { a, _ in a })
            marketplaceEnabled = flags["marketplace_enabled"] ?? false
        } catch {
            marketplaceEnabled = false
        }
    }

    func reset() {
        marketplaceEnabled = false
    }
}
