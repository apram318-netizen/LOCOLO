//
//  SupabaseManager.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//


import Foundation
import Supabase


/// Handles all communication with Supabase.
/// Basically our one-stop client to call stored procedures and interact with the database.
/// Keeps a shared instance so we don’t keep re-initializing the client everywhere.
class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient
    
    var currentUserId: String? {
        get { UserDefaults.standard.string(forKey: "supabaseUserId") }
        set { UserDefaults.standard.setValue(newValue, forKey: "supabaseUserId") }
    }

    // TODO(LOCOLO): Add the caching to firestore no sql only if the requested data is not available in cache | Status: completed
    
    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseURL)!,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }
    
}


// MARK: EXTENSION: SupabaseManager
/// Extension with the helper methods that actually call Supabase RPCs.
/// All async, clean, and return either IDs or just run stored procedures quietly.
extension SupabaseManager {
    
    /// Finds which loop a coordinate belongs to by calling the Supabase function find loop for point
    /// Returns the loop’s UUID if found, otherwise nil.
    func findLoop(forLat lat: Double, lon: Double) async throws -> UUID? {
        do {
            let result: Loop = try await client
                .rpc("find_loop_for_point", params: [
                    "p_lat": lat,
                    "p_lon": lon
                ])
                .execute()
                .value
            
            print(" find_loop_for_point raw response: \(result.id ?? "")")
            
            if let loopId = result.id {
                return UUID(uuidString: loopId)
            } else {
                print(" No loop found at this coordinate.")
                return nil
            }
        } catch {
            print(" Supabase RPC error: \(error)")
            throw error
        }
    }

    /// Updates the loop counter inside the supabase for a user (adds time spent in a loop).
    /// In case of errors to the call must check the supabase triggers this function uses on supabase.
    /// Basically wraps a stored procedure `update_loop_counter`.
    func updateLoopCounter(userId: String, loopId: UUID, hours: Double) async throws {
        let params: [String: AnyEncodable] = [
            "p_user": AnyEncodable(userId.lowercased()),
            "p_loop": AnyEncodable(loopId.uuidString.lowercased()),
            "p_hours": AnyEncodable(hours)
        ]
        _ = try await client.rpc("update_loop_counter", params: params).execute()
    }

    /// Marks a user as having left a loop.
    /// Simple Supabase RPC call — just updates state server-side.
    func markUserLeftLoop(userId: String, loopId: UUID) async throws {
        _ = try await client.rpc("mark_user_left_loop", params: [
            "p_user": userId.lowercased(),
            "p_loop": loopId.uuidString.lowercased()
        ]).execute()
    }
}

