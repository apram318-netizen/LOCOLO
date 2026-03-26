//
//  ProfileViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 4/11/2025.
//

import Foundation
import Supabase

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var places: [Place] = []
    @Published var assets: [DigitalAsset] = []
    @Published var error: String?

    private let client = SupabaseManager.shared.client

    // MARK: - Load User Posts
    /// Loads all posts created by a specific user.
    /// Discussion: Pulls posts directly from Supabase, filtering out deleted entries.
    /// - Parameter userId: The ID of the user whose posts should be fetched.
    func loadPosts(for userId: UUID) async {
        isLoading = true
        error = nil
        do {
            let results: [Post] = try await client
                .from("posts")
                .select("""
                    post_id,
                    author_id,
                    loop_id,
                    description,
                    media,
                    tags,
                    place_id,
                    visibility,
                    is_deleted,
                    created_at,
                    updated_at,
                    users:users(username, avatar_url)
                """)
                .eq("author_id", value: userId)
                .eq("is_deleted", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            posts = results
        } catch {
            self.error = error.localizedDescription
            print(" Failed to load posts: \(error)")
        }
        isLoading = false
    }
    
    
    
    // MARK: - Load Visited Places
    /// Loads all places a user has visited based on their visit records.
    /// Discussion: Fetches from the `visits` table, then resolves each places linked to each other
    /// - Parameter userId: The ID of the user whose visited places are being loaded.
    func loadPlaces(for userId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Fetch all visits for this user
            let visits: [Visit] = try await client
                .from("visits")
                .select("id, user_id, place_id")
                .eq("user_id", value: userId)
                .execute()
                .value

            print(" Found \(visits.count) visits for user \(userId)")

            guard !visits.isEmpty else {
                print(" No visits found for user \(userId)")
                self.places = []
                return
            }

            // Fetch all places concurrently
            let fetchedPlaces: [Place] = try await withThrowingTaskGroup(of: Place?.self) { group in
                for visit in visits {
                    group.addTask {
                        do {
                            let results: [Place] = try await self.client
                                .from("places")
                                .select("""
                                    place_id,
                                    loop_id,
                                    posted_by,
                                    name,
                                    description,
                                    place_image_url,
                                    trailer_media_url,
                                    created_at,
                                    location_id,
                                    verification_status
                                """)
                                .eq("place_id", value: visit.placeId)
                                .limit(1)
                                .execute()
                                .value

                            if let place = results.first {
                                print(" Loaded place for visit \(visit.placeId): \(place.name)")
                                return place
                            } else {
                                print(" No matching place found for \(visit.placeId)")
                                return nil
                            }

                        } catch {
                            print(" Failed to fetch place for \(visit.placeId): \(error)")
                            return nil
                        }
                    }
                }

                // Collect results
                var results: [Place] = []
                for try await result in group {
                    if let place = result { results.append(place) }
                }
                return results
            }

            // Update state
            DispatchQueue.main.async {
                self.places = fetchedPlaces.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
                print(" Loaded \(self.places.count) visited places total.")
            }

        } catch {
            self.error = error.localizedDescription
            print(" Failed to load visited places: \(error)")
        }
    }
    
    

    // MARK: - Load User Collection
    /// Fetches all digital assets owned or created by the user.
    /// Discussion: This builds the user’s “collection” tab view.
    /// - Parameter userId: The user whose digital assets are to be fetched.
    func loadUserCollection(userId: UUID) async {
        isLoading = true
        error = nil
        
        do {
            let response: [DigitalAsset] = try await client
                .from("digital_assets")
                .select("*")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            let decoded = response
            await MainActor.run {
                self.assets = decoded
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    
}
