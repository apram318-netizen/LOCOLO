//
//  OfferViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//

import Foundation


/// - Description: Handles all offer-related logic — fetching, creating, updating,
/// and sorting offers for a given digital asset. Also tracks submission and loading states.
@MainActor
final class OfferViewModel: ObservableObject {
    
    
    // MARK: - Published State
    @Published var offers: [Offer] = []            // all current offers
    @Published var highestOffer: Double?
    @Published var isLoading = false
    @Published var isSubmitting = false            // submission state for offer creation
    @Published var errorMessage: String?
    @Published var sortMode: SortMode = .highest

    private let repo = OfferRepository()

    // MARK: - Sorting Enum
    /// - Description: Determines how offers are displayed in the UI.
    enum SortMode: String, CaseIterable {
        case highest = "Highest"
        case newest = "Newest"
    }

    // MARK: FUNCTION: loadOffers
    /// - Description: Fetches all offers for a specific digital asset from Supabase.
    /// Applies sorting automatically based on the current `sortMode`.
    ///
    /// - Parameter assetId: The UUID of the asset whose offers are being loaded.
    func loadOffers(for assetId: UUID) async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await repo.fetchOffers(for: assetId)
            offers = sortOffers(fetched)
        } catch {
            errorMessage = "Failed to load offers: \(error.localizedDescription)"
        }
        isLoading = false
    }

    
    
    // MARK: FUNCTION: createOffer
    /// - Description: Creates a new offer for the given digital asset and refreshes the list.
    /// Returns a Bool indicating whether submission succeeded.
    ///
    /// - Parameters:
    ///   - assetId: The UUID of the asset being bid on
    ///   - buyerId: The UUID of the user placing the offer
    ///   - price: The amount offered
    /// - Returns: `true` if offer creation succeeded, `false` otherwise
    func createOffer(assetId: UUID, buyerId: UUID, price: Double) async -> Bool {
        guard price > 0 else {
            errorMessage = "Enter a valid offer amount."
            return false
        }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await repo.createOffer(assetId: assetId, buyerId: buyerId, price: price)
            await loadOffers(for: assetId)
            return true
        } catch {
            errorMessage = "Failed to create offer: \(error.localizedDescription)"
            return false
        }
    }
    
    
    

    // MARK: FUNCTION: updateOfferStatus
    /// - Description: Updates the status of an existing offer (e.g., accepted, withdrawn).
    /// Automatically reloads all offers after updating.
    ///
    /// - Parameters:
    ///   - offerId: The UUID of the offer being updated
    ///   - status: The new status string
    ///   - assetId: The asset the offer belongs to
    func updateOfferStatus(_ offerId: UUID, to status: String, for assetId: UUID) async {
        do {
            try await repo.updateOfferStatus(offerId: offerId, status: status)
            await loadOffers(for: assetId)
        } catch {
            errorMessage = "Failed to update offer: \(error.localizedDescription)"
        }
    }
    
    
    

    // MARK: FUNCTION: withdrawOffer
    /// - Description: Convenience wrapper to withdraw an offer.
    /// Internally just updates the status to `withdrawn`.
    ///
    /// - Parameters:
    ///   - offerId: The UUID of the offer to withdraw
    ///   - assetId: The UUID of the asset the offer belongs to
    func withdrawOffer(_ offerId: UUID, for assetId: UUID) async {
        await updateOfferStatus(offerId, to: "withdrawn", for: assetId)
    }

    
    
    // MARK: FUNCTION: loadHighestOffer
    /// - Description: Fetches and updates the current highest offer for an asset.
    ///
    /// - Parameter assetId: The UUID of the asset to check
    func loadHighestOffer(for assetId: UUID) async {
        do {
            highestOffer = try await repo.fetchHighestOffer(for: assetId)
        } catch {
            print(" Error loading highest offer:", error)
        }
    }
    
    
    

    // MARK: FUNCTION: setSort
    /// - Description: Changes the sorting mode and re-sorts existing offers.
    /// Useful when the user toggles sorting options in the UI.
    ///
    /// - Parameter mode: The new `SortMode` to apply
    func setSort(_ mode: SortMode) {
        sortMode = mode
        offers = sortOffers(offers)
    }
    
    
    

    // MARK: Helper: sortOffers
    /// - Description: Sorts a given list of offers based on the current `sortMode`.
    /// - Parameter list: Array of offers to sort
    /// - Returns: Sorted array of offers
    private func sortOffers(_ list: [Offer]) -> [Offer] {
        switch sortMode {
        case .highest:
            return list.sorted { $0.price > $1.price }
        case .newest:
            return list.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    
    
}
