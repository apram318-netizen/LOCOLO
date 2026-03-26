//
//  HypeViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//

import Foundation
import SwiftUI

@MainActor
class HypeViewModel: ObservableObject {
    
    @Published var hypes: [Hype] = []               // all hype entries for a given post
    @Published var isHypedByUser: Bool = false      // whether the current user has hyped this post
    
    let post: Post
    let currentUserId: UUID
    
    init(post: Post, currentUserId: UUID) {
        self.post = post
        self.currentUserId = currentUserId
    }
    
    // MARK: FUNCTION: loadHypes
    /// - Description: Loads all the hype records for a given post from Supabase.
    /// Also determines if the current user has already hyped it.
    ///
    /// this class Currently performs a full reload each time. Later, this could switch to just some incremental updates.
    /// I can  also try to  use Supabase's real-time subscriptions so that hype counts update live.
    ///  I want to bundle the hypes and flush them together to avoid too many database calls in future: JUst like insta does it
    func loadHypes() {
        Task {
            do {
                let result: [Hype] = try await SupabaseManager.shared.client
                    .from("hypes")
                    .select("*, user:users(user_id, username, avatar_url)")
                    .eq("post_id", value: post.id)
                    .execute()
                    .value
                
                await MainActor.run {
                    self.hypes = result
                    self.isHypedByUser = result.contains { $0.userId == currentUserId }
                }
            } catch {
                print("Error loading hypes: \(error)")
            }
        }
    }
    
    
    
    // MARK: FUNCTION: toggleHype
    /// - Description: Toggles the hype state for the current user on this post.
    /// If already hyped, removes the record. If not, creates a new one.
    ///
    /// - Discussion:
    ///   Currently writes directly to Supabase each time.
    ///   Later, I will probably  add  updates or a checks  to avoid double taps.
    func toggleHype() {
        Task {
            if isHypedByUser {
                // Un-hype: remove record
                do {
                    try await SupabaseManager.shared.client
                        .from("hypes")
                        .delete()
                        .eq("post_id", value: post.id)
                        .eq("user_id",  value: currentUserId)
                        .execute()
                    
                    await MainActor.run {
                        self.isHypedByUser = false
                        self.hypes.removeAll { $0.userId == currentUserId }
                    }
                } catch {
                    print("Error un-hyping: \(error)")
                }
            } else {
                // Add hype: insert record
                let newHype = [
                    "post_id": post.id!.uuidString,
                    "user_id": currentUserId.uuidString
                ]
                
                do {
                    try await SupabaseManager.shared.client
                        .from("hypes")
                        .insert(newHype)
                        .execute()
                    
                    await MainActor.run {
                        self.isHypedByUser = true
                        self.hypes.append(Hype(
                            id: UUID(),
                            userId: currentUserId,
                            postId: post.id!,
                            createdAt: Date(),
                            user: nil
                        ))
                    }
                } catch {
                    print("Error hyping: \(error)")
                }
            }
        }
    }
}

// Resources for this file( It was just some tiny research on how insta does it, but not something I dived deep into and implemented for the app:) Still:
// Its a very useful resource btw, refer to it for ideas for my future functionality:
// https://sproutsocial.com/insights/instagram-algorithm/
