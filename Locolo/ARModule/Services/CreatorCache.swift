//
//  CreatorCache.swift
//  Locolo
//
//  One shared, batch-loading cache of lightweight user rows (ARCreator) so
//  feed cards, comments, the inbox, activity and search never refetch the
//  same profile — and every surface shows the same avatar/name.
//

import Foundation
import Combine
import Supabase

@MainActor
final class CreatorCache: ObservableObject {
    static let shared = CreatorCache()

    @Published private(set) var creators: [UUID: ARCreator] = [:]

    static let columns = "user_id, username, name, avatar_url, verified_flags"

    private let client = SupabaseManager.shared.client
    private var inFlight: Set<UUID> = []

    private init() {}

    func creator(_ id: UUID) -> ARCreator? { creators[id] }

    func insert(_ list: [ARCreator]) {
        for c in list { creators[c.id] = c }
    }

    /// Fetches any ids not already cached (or being fetched) in one request.
    func load(_ ids: [UUID]) async {
        let missing = Array(Set(ids).subtracting(creators.keys).subtracting(inFlight))
        guard !missing.isEmpty else { return }
        inFlight.formUnion(missing)
        defer { inFlight.subtract(missing) }
        do {
            let rows: [ARCreator] = try await client
                .from("users")
                .select(Self.columns)
                .in("user_id", values: missing.map(\.uuidString))
                .execute()
                .value
            insert(rows)
        } catch {
            print("CreatorCache load failed:", error.localizedDescription)
        }
    }

    /// Replaces a cached row after the user edits their own profile.
    func refresh(_ id: UUID) async {
        creators[id] = nil
        await load([id])
    }

    func reset() {
        creators = [:]
    }
}
