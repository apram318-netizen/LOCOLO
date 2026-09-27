//
//  PeopleSearch.swift
//  Locolo
//
//  Finds creators by username or display name for the Search tab's People
//  results and the new-message picker. Blocked users and yourself are
//  filtered out; results are folded into CreatorCache.
//

import Foundation
import Supabase

enum PeopleSearch {
    @MainActor
    static func search(_ query: String, limit: Int = 20) async -> [ARCreator] {
        // Strip characters that are syntax in a PostgREST or() filter or LIKE.
        let cleaned = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .filter { !",()%*\\:\"".contains($0) }
            .replacingOccurrences(of: "_", with: "\\_")
        guard cleaned.count >= 1 else { return [] }

        do {
            let rows: [ARCreator] = try await SupabaseManager.shared.client
                .from("users")
                .select(CreatorCache.columns)
                .or("username.ilike.%\(cleaned)%,name.ilike.%\(cleaned)%")
                .limit(limit)
                .execute()
                .value
            CreatorCache.shared.insert(rows)
            let me = SupabaseManager.shared.currentUserId.flatMap(UUID.init(uuidString:))
            let blocked = SafetyService.shared.blockedUserIds
            let lowered = cleaned.lowercased()
            return rows
                .filter { $0.id != me && !blocked.contains($0.id) }
                .sorted { rank($0, lowered) < rank($1, lowered) }
        } catch {
            print("People search failed:", error.localizedDescription)
            return []
        }
    }

    /// Exact handle first, then prefix matches, then verified, then the rest.
    private static func rank(_ c: ARCreator, _ q: String) -> Int {
        let handle = c.username.lowercased()
        if handle == q { return 0 }
        if handle.hasPrefix(q) || (c.name?.lowercased().hasPrefix(q) ?? false) { return c.isVerified ? 1 : 2 }
        return c.isVerified ? 3 : 4
    }
}
