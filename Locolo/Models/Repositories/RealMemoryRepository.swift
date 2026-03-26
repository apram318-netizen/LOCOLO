//
//  RealMemoryRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 7/10/2025.
//

import Foundation
import Supabase


/// Uses Supabase for storage and retrieval.
class RealMemoryRepository {
    private let client = SupabaseManager.shared.client

    // MARK: FUNCTION: createRealMemory
    /// - Description: Uploads a new real memory to Supabase.
    /// Usually called when a use adds a place or a post
    ///
    /// - Parameter memory: The RealMemory object to insert
    /// - Throws: If the insert fails
    func createRealMemory(_ memory: RealMemory) async throws {
        try await client
            .from("real_memories")
            .insert(memory)
            .execute()
    }
    
    
    

    // MARK: FUNCTION: fetchRealMemories
    /// - Description: Fetches all real memories attached to a specific post.
    ///
    /// - Parameter postId: The UUID of the post
    /// - Returns: A list of RealMemory  objects linked to that post
    func fetchRealMemories(forPost postId: UUID) async throws -> [RealMemory] {
        let response: [RealMemory] = try await client
            .from("real_memories")
            .select()
            .eq("post_id", value: postId)
            .execute()
            .value
        return response
    }
    
    

    // MARK: FUNCTION: fetchAll
    /// - Description: Fetches all real memories created by a specific user.
    /// Great for building out a “memories gallery” in a user’s profile.
    ///
    /// - Parameter userId: The UUID of the user
    /// - Returns: A list of all RealMemory entries authored by that user
    func fetchAll(forUser userId: UUID) async throws -> [RealMemory] {
        let response: [RealMemory] = try await client
            .from("real_memories")
            .select()
            .eq("author_id", value: userId)
            .execute()
            .value
        return response
    }
    
    
}

// The repository is still half finished. For the simiplicity of this app. We dont have the functionality of real memory right now.
