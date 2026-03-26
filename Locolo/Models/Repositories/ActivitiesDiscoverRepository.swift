//
//  ActivitiesDiscoverRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 30/10/2025.
//

import Foundation

/// Pulls from Supabase, caches locally, and formats them into lightweight UI models.
/// Basically the behind-the-scenes for the Discover screen’s activity feed.

class ActivitiesDiscoverRepository {
    private let client = SupabaseManager.shared.client
    private let cacheStore = CacheStore.shared

    
    
    // MARK: FUNCTION: fetchActivities
    /// - Description: Loads activities for the Discover screen.
    /// Tries cache first for instant results, then refreshes from Supabase if needed.
    /// Also pre-caches images so they're ready offline.
    /// Filters activities by the user's active loop_id to only show relevant activities.
    func fetchActivities() async throws -> [ActivityItem] {
        // Get active loop ID from UserDefaults (same pattern as DiscoverRepository)
        guard let loopIdString = UserDefaults.standard.string(forKey: "selectedLoopId") else {
            print(" No selected loop ID found - returning empty activities")
            return []
        }

        // Filter at database level - only fetch activities for this loop
        // Note: We don't use cache here because cache doesn't filter by loop_id
        // and could return activities from a different loop
        let response: [Activity] = try await client
            .from("activities")
            .select()
            .eq("loop_id", value: loopIdString)
            .execute()
            .value

        await cacheStore.upsertActivities(response)
        let imageURLs = response.compactMap { $0.activityImageUrl }.compactMap(URL.init(string:))
        await cacheMedia(for: imageURLs)

        return response.map(makeActivityItem(from:))
    }
    
    

    // MARK: FUNCTION: makeActivityItem
    /// - Description: Converts a full `Activity` into a smaller `ActivityItem` for the cards UI.
    /// Adds a few placeholders like price, duration, and some fake hype stats for now.
    private func makeActivityItem(from activity: Activity) -> ActivityItem {
        ActivityItem(
            id : activity.id,
            name: activity.name,
            type: activity.categoryId?.uuidString.prefix(10).description ?? "General",
            duration: "Varies",
            price: "Check details",
            description: activity.description ?? "No description available",
            rating: 4.5,
            participants: Int.random(in: 100...2000),
            image: activity.activityImageUrl ?? "https://images.unsplash.com/photo-1501339847302-ac426a4a7cbb?w=200&h=150&fit=crop",
            hypes: Int.random(in: 50...500)
        )
    }
    
    

    // MARK: Helper: cacheMedia
    /// - Description: Downloads and caches activity images if missing.
    /// Just spins up a task group and quietly stores images in the background.
    private func cacheMedia(for urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls where shouldDownload(url: url) {
                group.addTask { await self.downloadAndCache(url: url) }
            }
        }
    }
    
    

    // MARK: Helper: shouldDownload
    /// - Description: Checks if the image already exists locally before downloading again.
    /// Simple check to avoid wasting bandwidth.
    private func shouldDownload(url: URL) -> Bool {
        guard url.scheme != "file" else { return false }
        return MediaCache.shared.localURL(forRemoteURL: url) == nil
    }
    
    

    // MARK: Helper: downloadAndCache
    /// - Description: Pulls down the image and saves it into MediaCache.
    /// Logs errors but doesn’t crash if a download fails
    private func downloadAndCache(url: URL) async {
        guard shouldDownload(url: url) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = MediaCache.shared.store(data: data, for: url)
        } catch {
            print(" Failed to cache activity image \(url): \(error.localizedDescription)")
        }
    }
}
