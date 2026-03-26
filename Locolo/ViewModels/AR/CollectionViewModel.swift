//
//  CollectionViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 2/11/2025.
//



import Foundation
import Supabase


/// so it is using their personal AR collection. Connects directly to Supabase for now.
@MainActor
class CollectionViewModel: ObservableObject {
    // MARK: - Published State
    @Published var assets: [DigitalAsset] = []     // all digital assets owned by the user
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    // MARK: FUNCTION: loadUserCollection
    /// - Description: Loads all digital assets that belong to the given user ID.
    /// Pulls from Supabase and sorts results by creation date (newest first).
    ///
    /// - Parameter userId: The UUID of the user whose collection is being loaded
    func loadUserCollection(userId: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            let response: [DigitalAsset] = try await client
                .from("digital_assets")
                .select("*")
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            await MainActor.run {
                self.assets = response
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load collection: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
}
