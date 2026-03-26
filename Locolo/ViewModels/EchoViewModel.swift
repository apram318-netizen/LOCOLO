//
//  EchoViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/10/2025.
//

import Foundation
import SwiftUI

@MainActor
class EchoViewModel: ObservableObject {
    
    @Published var echoes: [Echo] = []
    @Published var newEchoText: String = ""
    
    let post: Post
    
    init(post: Post) {
        self.post = post
    }
    
    // MARK: FUNCTION: loadEchoes
    /// - Description: Loads all echoes (comments) for the given post from Supabase.
    /// Includes author data for display. For now, this just fetches once on load.
    ///
    /// - Parameter post: The post to load echoes for
    ///
    /// - Discussion:
    ///   This should later be improved with:
    ///   • Pagination or incremental loading to handle long comment threads
    ///   • Real-time updates using Supabase’s subscription feature
    ///   • Better error handling and retry logic
    func loadEchoes(for post: Post) {
        Task {
            do {
                let result: [Echo] = try await SupabaseManager.shared.client
                    .from("echoes")
                    .select("*, author:users(user_id, username, avatar_url)")
                    .eq("post_id",value:  post.id)
                    .order("created_at", ascending: true)
                    .execute()
                    .value
                                
                print("fetch result: \(result)")

                await MainActor.run {
                    self.echoes = result
                }
            } catch {
                print("Error loading echoes: \(error)")
            }
        }
    }
    
    
    
    // MARK: FUNCTION: addEcho
    /// - Description: Adds a new echo (comment) for the selected post.
    /// Pushes the data to Supabase and updates the local array immediately.
    ///
    /// - Parameters:
    ///   - post: The post the echo belongs to
    ///   - currentUserId: The user adding the echo
    ///
    /// - Discussion:
    ///   • Later, we could add a “sending” indicator or retry on failure
    ///   • Reply chaining can be added using `parentEchoId`
    func addEcho(to post: Post , currentUserId: UUID) {
        guard !newEchoText.isEmpty else { return }
        
        let echoText = newEchoText
        Task {
            do {
                let newEcho = Echo(
                    id: UUID(),
                    postId: post.id! ,
                    userId: currentUserId ,
                    parentEchoId: nil,
                    content: echoText,
                    createdAt: Date(),
                    updatedAt: nil,
                    isDeleted: false,
                    author: nil
                )
                
                let response = try await SupabaseManager.shared.client
                    .from("echoes")
                    .insert(newEcho)
                    .execute()

                print("Insert response: \(response)")
                print("Inserting echo with content: \(newEchoText)")
                
                await MainActor.run {
                    echoes.append(newEcho)
                    newEchoText = ""
                }
            } catch {
                print("Error adding echo: \(error)")
            }
        }
    }
    
    
}
