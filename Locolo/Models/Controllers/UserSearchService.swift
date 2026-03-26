//
//  UserSearchService.swift
//  Locolo
//
//  Created by Apramjot Singh on 29/10/2025.
//


import Supabase

/// Basically just wraps a query to the “users” table with some filters.
/// Runs on the main actor since results are usually bound to UI updates.
@MainActor
final class UserSearchService {
    private let client = SupabaseManager.shared.client   // reuse the shared Supabase client
    
    /// Searches users whose username matches the keyword, excluding the current user.
    /// - Parameters:
    ///   - keyword: What the user typed in the search bar
    ///   - excludeUserId: The current user's id (so you don't see yourself)
    /// - Returns: A list of matching `SupabaseUser`s
    func searchUsers(keyword: String, excludeUserId: String) async -> [SupabaseUser] {
        
        guard !keyword.isEmpty else { return [] } // don't bother searching empty text

        do {
            let response = try await client
                .from("users")
                .select("user_id, username, email, name, avatar_url") // pick only what we need
                .ilike("username", pattern: "%\(keyword)%")          // case-insensitive match
                .neq("user_id", value: excludeUserId)                // skip current user
                .execute()
                .value as [SupabaseUser]
            
            return response
            
        } catch {
            print(" Supabase search failed:", error)
            return []
        }
    }
}



/// Keeps only minimal info for display — id, name, username, and avatar.
struct SupabaseUser: Decodable, Identifiable {
    let user_id: String
    let name: String?
    let username: String?
    let avatar_url: String?

    // Just makes it work nicely with SwiftUI Lists and ForEach
    var id: String { user_id }
}
