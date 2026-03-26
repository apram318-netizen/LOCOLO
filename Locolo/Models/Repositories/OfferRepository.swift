//
//  OfferRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 9/11/2025.
//
//  This file talks to the offers table in Supabase.
//  It loads offers, creates offers, updates offers,
//  and gets the highest offer for an asset.


import Foundation
import Supabase
import Combine

final class OfferRepository {
    private let client = SupabaseManager.shared.client


    // MARK: Fetch all offers for an asset
    /// - Description: Loads every offer made on the asset. Newest offers come first.
    /// - Parameters: assetId is the asset we want to check.
    /// - Returns: A list of Offer objects.
    func fetchOffers(for assetId: UUID) async throws -> [Offer] {
        try await client
            .from("offers")
            .select("*")
            .eq("asset_id", value: assetId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }


    // MARK: Create a new offer
    /// - Description: Makes a new offer with a pending status.
    /// - Parameters: assetId is the asset, buyerId is who is offering, price is the amount.
    /// - Returns: Nothing.
    func createOffer(assetId: UUID, buyerId: UUID, price: Double) async throws {
        let payload: [String: AnyEncodable] = [
            "asset_id": AnyEncodable(assetId),
            "buyer_id": AnyEncodable(buyerId),
            "amount": AnyEncodable(price),
            "status": AnyEncodable("pending")
        ]

        try await client
            .from("offers")
            .insert([payload])
            .execute()
    }


    // MARK: Update offer status
    /// - Description: Updates the status of the offer. Used for accept, reject, or withdraw.
    /// - Parameters: offerId is the offer to update, status is the new status.
    /// - Returns: Nothing.
    func updateOfferStatus(offerId: UUID, status: String) async throws {
        try await client
            .from("offers")
            .update(["status": status])
            .eq("offer_id", value: offerId)
            .execute()
    }


    // MARK: Highest offer
    /// - Description: Gets the highest offer for an asset using a Supabase function.
    /// - Parameters: assetId is the asset we are checking.
    /// - Returns: The highest amount or nil.
    func fetchHighestOffer(for assetId: UUID) async throws -> Double? {
        let rows: [[String: Double?]] = try await client
            .rpc("highest_offer_for_asset", params: ["p_asset_id": assetId.uuidString])
            .execute()
            .value

        return rows.first?["highest_offer"] as? Double
    }
}
