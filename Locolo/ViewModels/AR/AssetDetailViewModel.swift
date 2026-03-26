//
//  AssetDetailViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//

import Foundation


/// Handles fetching all offers, creating new ones, and tracking the highest bid in real-time.
@MainActor
final class AssetDetailViewModel: ObservableObject {
    // MARK: - Published State
    @Published var offers: [Offer] = []          // all offers on the asset
    @Published var highestOffer: Double?         // current top offer
    @Published var isLoading = false             // loading spinner control
    @Published var errorMessage: String?         // user-facing error message

    private let repo = DigitalAssetRepository()

    // MARK: FUNCTION: loadOffers
    /// - Description: Loads all offers for a given digital asset from Supabase.
    /// Automatically updates the highest offer and resets any existing error.
    ///
    /// - Parameter assetId: The UUID of the digital asset
    func loadOffers(for assetId: UUID) async {
        isLoading = true
        do {
            let fetched = try await repo.fetchOffers(for: assetId)
            offers = fetched
            highestOffer = fetched.map(\.price).max()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load offers: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: FUNCTION: createOffer
    /// - Description: Creates a new offer for the selected digital asset,
    /// then refreshes the list of offers to show the updated state.
    ///
    /// - Parameters:
    ///   - assetId: The UUID of the asset being bid on
    ///   - buyerId: The UUID of the user placing the offer
    ///   - price: The offer price
    func createOffer(assetId: UUID, buyerId: UUID, price: Double) async {
        do {
            _ = try await repo.createOffer(assetId: assetId, buyerId: buyerId, price: price)
            await loadOffers(for: assetId)
        } catch {
            errorMessage = "Failed to create offer: \(error.localizedDescription)"
        }
    }
}
