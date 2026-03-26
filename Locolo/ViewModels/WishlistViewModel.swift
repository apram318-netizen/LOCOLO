//
//  WishlistViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/11/2025.
//

import Foundation
import Supabase

@MainActor
class WishlistViewModel: ObservableObject {
    @Published var items: [DigitalAsset] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    // MARK: - Load Wishlist
    /// Loads all digital assets saved to a user’s wishlist.
    /// Discussion: Performs a join between `wishlist` and `digital_assets` tables.
    /// - Parameter userId: The ID of the user whose wishlist is being fetched.
    func loadWishlist(for userId: UUID) async {
        isLoading = true
        errorMessage = nil

        do {
            // Join wishlist → digital_assets
            let response: [WishlistJoin] = try await client
                .from("wishlist")
                .select("digital_assets(*)")
                .eq("user_id", value: userId)
                .order("added_at", ascending: false)
                .execute()
                .value

            struct WishlistJoin: Decodable {
                let digital_assets: DigitalAsset
            }

            let decoded = response

            await MainActor.run {
                self.items = decoded.map { $0.digital_assets }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    

    // MARK: - Add to Wishlist
    /// Adds a given digital asset to the user’s wishlist.
    /// - Parameters:
    ///   - userId: The current user’s ID.
    ///   - assetId: The ID of the asset being added.
    func addToWishlist(userId: UUID, assetId: UUID) async {
        do {
            try await client
                .from("wishlist")
                .insert([
                    "user_id": userId.uuidString,
                    "asset_id": assetId.uuidString
                ])
                .execute()
            print(" Added to wishlist")
        } catch {
            print(" Failed to add to wishlist:", error)
        }
    }
    
    

    // MARK: - Remove from Wishlist
    /// Removes an asset from the user’s wishlist.
    /// Discussion: Updates both the database and local list immediately.
    /// - Parameters:
    ///   - userId: The current user’s ID.
    ///   - assetId: The ID of the asset to remove.
    func removeFromWishlist(userId: UUID, assetId: UUID) async {
        do {
            try await client
                .from("wishlist")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("asset_id", value: assetId.uuidString)
                .execute()

            self.items.removeAll { $0.id == assetId }
            print(" Removed from wishlist")
        } catch {
            print(" Failed to remove from wishlist:", error)
        }
    }
    
    
}
