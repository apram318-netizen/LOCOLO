//
//  UsersRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//
import Foundation
/// Pulls from Supabase and syncs everything locally in cache for quick lookups and offline access.
class UsersRepository {
    private let client = SupabaseManager.shared.client
    private let cacheStore = CacheStore.shared

    
    
    
    // MARK: FUNCTION: getUser (by ID)
    /// - Description: Fetches a user by their unique ID, using cache first to make it run faster/
    /// If not cached then it tries to  retrieves from Supabase and updates the cache.
    ///
    /// - Parameter id: The user’s UUID
    /// - Returns: A User object if found, or nil if no match exists
    /// - Throws: If the Supabase query fails
    func getUser(by id: UUID) async throws -> User? {
        if let cached = cacheStore.fetchUserDomain(id: id) {
            return cached
        }

        let response: [User] = try await client
            .from("users")
            .select()
            .eq("user_id", value: id)
            .limit(1)
            .execute()
            .value

        if let user = response.first {
            await cacheStore.upsertUser(user)
            if let avatar = user.avatarUrl {
                await cacheMedia(for: avatar)
            }
            return user
        }
        return nil
    }
    
    
    

    // MARK: FUNCTION: getUser (by username)
    /// - Description: Fetches a user by their username, checking cache first before hitting Supabase.
    /// Used for profile lookups and messaging flows.
    ///
    /// - Parameter username: The user’s username
    /// - Returns: A User object if found, or nil otherwise
    /// - Throws: If the Supabase query fails
    func getUser(byUsername username: String) async throws -> User? {
        if let cached = cacheStore.fetchUserDomain(username: username) {
            return cached
        }

        let response: [User] = try await client
            .from("users")
            .select()
            .eq("username", value: username)
            .limit(1)
            .execute()
            .value

        if let user = response.first {
            await cacheStore.upsertUser(user)
            if let avatar = user.avatarUrl {
                await cacheMedia(for: avatar)
            }
            return user
        }
        return nil
    }
    
    
    

    // MARK: FUNCTION: createUser
    /// - Description: Creates a new user in Supabase and stores it in cache.
    /// Usually called during onboarding or sign-up.
    ///
    /// - Parameter user: The User  object containing profile info
    /// - Throws: If Supabase insert fails
    func createUser(_ user: User) async throws {
        try await client
            .from("users")
            .insert(user)
            .execute()

        await cacheStore.upsertUser(user)
        if let avatar = user.avatarUrl {
            await cacheMedia(for: avatar)
        }
    }
    
    

    // MARK: FUNCTION: updateUser
    /// - Description: Updates user data in Supabase and mirrors it locally in cache.
    ///
    /// I am currently using when editing a profile or will use it to change avatars
    /// However its full usage flow is currently not fully completed .
    ///
    /// - Parameters:
    ///   - id: The user’s UUID
    ///   - data: The updated Users model
    /// - Throws: If Supabase update fails
    func updateUser(_ id: UUID, data: User) async throws {
        try await client
            .from("users")
            .update(data)
            .eq("user_id", value: id)
            .execute()

        await cacheStore.upsertUser(data)
        if let avatar = data.avatarUrl {
            await cacheMedia(for: avatar)
        }
    }

    
    
    
    // MARK: Helper: cacheMedia
    /// - Description: Downloads and caches a user’s avatar locally.
    ///
    /// Quietly skips if the image is already cached or local.
    ///Avatar's will be introduced in it later.
    ///
    /// - Parameter url: The remote URL of the user’s avatar
    private func cacheMedia(for url: URL) async {
        guard url.scheme != "file",
              MediaCache.shared.localURL(forRemoteURL: url) == nil else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = MediaCache.shared.store(data: data, for: url)
        } catch {
            print(" Failed to cache avatar at \(url): \(error.localizedDescription)")
        }
    }
}
