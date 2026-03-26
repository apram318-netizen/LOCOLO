//
//  DigitalAssetRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 2/11/2025.
//

import Foundation
import Supabase
import SwiftUI

// MARK: FILE: DigitalAssetRepository
/// - Description: Handles fetching, caching, and offer management for digital assets.
/// Think of this as the AR gallery main logiv and  it talks to Supabase, caches locally,
/// and manages offers tied to each asset.
@MainActor
final class DigitalAssetRepository {
    private let client = SupabaseManager.shared.client
    private let cacheStore = CacheStore.shared

    // MARK: FUNCTION: fetchAll
    /// - Description: Loads all digital assets, using cache first if available.
    /// - Parameter limit: Optional cap on how many assets to load
    /// - Returns: A list of `DigitalAsset` objects
    func fetchAll(limit: Int? = nil) async -> [DigitalAsset] {
        let cached = cacheStore.fetchDigitalAssets(limit: limit)
        if !cached.isEmpty {
            return cached
        }

        do {
            var query = client.from("digital_assets_flat")
                .select()
                .order("created_at", ascending: false)
            if let limit { query = query.limit(limit) }

            let assets: [DigitalAsset] = try await query.execute().value

            //  fill offers BEFORE caching
            let newAssets = await attachHighestOffers(to: assets)

            //  Cache the updated version
            await cacheMedia(for: newAssets)
            await cacheStore.upsertDigitalAssets(newAssets)

            //  Return filled version
            return newAssets
            
        } catch {
            print(" fetchAll failed:", error)
            return []
        }
    }
    
    
    

    // MARK: FUNCTION: fetchByUser
    /// - Description: Fetches all digital assets owned by a given user.
    /// - Parameter userId: The user’s UUID string
    /// - Returns: A list of that user’s assets, cached and sorted by creation date
    func fetchByUser(_ userId: String) async -> [DigitalAsset] {
        if let uuid = UUID(uuidString: userId) {
            let cached = cacheStore.fetchDigitalAssets(for: uuid)
            if !cached.isEmpty {
                return cached
            }
        }

        do {
            let assets: [DigitalAsset] = try await client.from("digital_assets")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .execute()
                .value

            await cacheMedia(for: assets)
            await cacheStore.upsertDigitalAssets(assets)
            return assets
        } catch {
            print(" fetchByUser failed:", error)
            return []
        }
    }
    
    

    
    // MARK: FUNCTION: fetchOffers
    /// - Description: Loads all offers for a specific asset.
    /// - Parameter assetId: The asset’s UUID
    /// - Returns: A list of Offer objects
    func fetchOffers(for assetId: UUID) async throws -> [Offer] {
        try await client
            .from("offers")
            .select("*")
            .eq("asset_id", value: assetId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }
    
    
    

    // MARK: FUNCTION: fetchHighestOffer
    /// - Description: Finds the highest offer price for a given asset.
    /// - Parameter assetId: The asset’s UUID
    /// - Returns: The highest offer amount, or nil if no offers exist
    func fetchHighestOffer(for assetId: UUID) async throws -> Double? {
        let offers: [Offer] = try await fetchOffers(for: assetId)
        return offers.map(\.price).max()
    }
    
    
    

    // MARK: FUNCTION: createOffer
    /// - Description: Creates a new offer on a digital asset.
    /// - Parameters:
    ///   - assetId: The asset being offered on
    ///   - buyerId: The user making the offer
    ///   - price: The offer price
    /// - Returns: The new `Offer` object
    func createOffer(assetId: UUID, buyerId: UUID, price: Double) async throws -> Offer {
        let newOffer = Offer(
            id: UUID(),
            assetId: assetId,
            buyerId: buyerId,
            price: price,
            status: "pending",
            createdAt: Date()
        )
        try await client.from("offers").insert([newOffer]).execute()
        return newOffer
    }
    
    
    

    // MARK: FUNCTION: updateOfferStatus
    /// - Description: Updates the status of an existing offer (e.g., accepted, declined).
    /// - Parameters:
    ///   - offerId: The offer’s UUID
    ///   - status: The new status string
    func updateOfferStatus(offerId: UUID, status: String) async throws {
        try await client
            .from("offers")
            .update(["status": status])
            .eq("id", value: offerId)
            .execute()
    }
    
    
    

    // MARK: Helper: cacheMedia
    /// - Description: Downloads and caches media files (models, thumbnails, panoramas).
    /// Called after every fetch to make sure AR assets load instantly next time.
    private func cacheMedia(for assets: [DigitalAsset]) async {
        guard !assets.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for asset in assets {
                if let fileURL = URL(string: asset.fileUrl), shouldDownload(url: fileURL) {
                    group.addTask { await self.downloadAndCache(url: fileURL, requireImage: false) }
                }
                if let thumb = asset.thumbUrl, let url = URL(string: thumb), shouldDownload(url: url) {
                    group.addTask { await self.downloadAndCache(url: url, requireImage: true) }
                }
                if let pano = asset.panoramaUrl, let url = URL(string: pano), shouldDownload(url: url) {
                    group.addTask { await self.downloadAndCache(url: url, requireImage: false) }
                }
            }
        }
    }
    
    
    

    // MARK: Helper: shouldDownload
    /// - Description: Checks if a given media URL already exists in the cache.
    /// - Parameter url: The file’s remote URL
    /// - Returns: `true` if we should download it, `false` if it’s already cached
    private func shouldDownload(url: URL) -> Bool {
        guard url.scheme != "file" else { return false }
        return MediaCache.shared.localURL(forRemoteURL: url) == nil
    }
    
    
    

    // MARK: Helper: downloadAndCache
    /// - Description: Downloads media from the remote URL and stores it in `MediaCache`.
    ///
    /// There is an update to the function I am making in version after 12 :40 am 12th  november 2025
    /// Update: The function has been changed to check if the downloaded url actually has data if not we dont download
    ///
    /// - Parameter url: The file’s remote URL
    private func downloadAndCache(url: URL, requireImage: Bool) async {
        guard shouldDownload(url: url) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !data.isEmpty else {
                print("Skipping empty download for \(url)")
                return
            }
            if requireImage && UIImage(data: data) == nil {
                print("Skipping non-image data for \(url)")
                return
            }
            _ = MediaCache.shared.store(data: data, for: url)
        } catch {
            print("Failed to cache digital asset at \(url): \(error.localizedDescription)")
        }
    }
    
    
    // MARK: Helper: downloadAndCache
    /// - Description: This function fetches for the highest offers and attach them to the digital assets.
    ///
    ///I am using this function to make things easier to fetch the highest offers to be displayed inside the offers screen
    ///Would not need to fetch offers for anything
    ///
    /// - Parameter assets: digital asssets without highest offers fetch
    func attachHighestOffers(to assets: [DigitalAsset]) async -> [DigitalAsset] {
        await withTaskGroup(of: (UUID, Double?).self) { group in
            
            for asset in assets {
                group.addTask {
                    let highest = try? await self.fetchHighestOffer(for: asset.id)
                    return (asset.id, highest)
                }
            }
            
            var highestMap: [UUID: Double?] = [:]
            
            for await (id, highest) in group {
                highestMap[id] = highest
            }
            
            var updated = assets
            for i in 0..<updated.count {
                updated[i] = DigitalAsset(
                    id: updated[i].id,
                    name: updated[i].name,
                    userId: updated[i].userId,
                    locationId: updated[i].locationId,
                    fileUrl: updated[i].fileUrl,
                    thumbUrl: updated[i].thumbUrl,
                    fileType: updated[i].fileType,
                    category: updated[i].category,
                    description: updated[i].description,
                    hypeCount: updated[i].hypeCount,
                    viewCount: updated[i].viewCount,
                    createdAt: updated[i].createdAt,
                    panoramaUrl: updated[i].panoramaUrl,
                    visibility: updated[i].visibility,
                    interactionType: updated[i].interactionType,
                    locationName: updated[i].locationName,
                    latitude: updated[i].latitude,
                    longitude: updated[i].longitude,
                    rotationX: updated[i].rotationX,
                    rotationY: updated[i].rotationY,
                    rotationZ: updated[i].rotationZ,
                    scaleX: updated[i].scaleX,
                    scaleY: updated[i].scaleY,
                    scaleZ: updated[i].scaleZ,
                    isForSale: updated[i].isForSale,
                    acceptsOffers: updated[i].acceptsOffers,
                    currentValue: updated[i].currentValue,
                    boughtPrice: updated[i].boughtPrice,
                    highestOffer: highestMap[updated[i].id] ?? nil,
                    activeOffers: nil
                )
            }
            
            return updated
        }
    }

    
}
