//
//  PlacesRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 18/9/2025.
//


import Foundation
import Supabase



/// Talks to Supabase for the heavy lifting, and CacheStore for offline support.
/// Used throughout the app in place view models and search flows.
protocol PlacesRepositoryProtocol {
    func addPlace(_ place: PostPlace) async throws
    func deletePlace(by id: UUID, completion: @escaping (Result<Void, Error>) -> Void)
    func getPlace(by id: UUID) async throws -> Place?
    func getPlaces(forLoop loopID: UUID, completion: @escaping (Result<[Place], Error>) -> Void)
    func getPlacesNearby(latitude: Double, longitude: Double, radiusMeters: Double, completion: @escaping (Result<[Place], Error>) -> Void)
    func searchPlacesByName(_ query: String) async throws -> [Place]
    func checkNearbyPlaces(lat: Double, lon: Double, radiusMeters: Double) async throws -> [Place]
    func refreshPlaces(forLoop loopID: UUID) async throws -> [Place]
    // TODO: add Google Places integration later when ready
}



class PlacesRepository: PlacesRepositoryProtocol {
    private let client = SupabaseManager.shared.client
    private let cacheStore = CacheStore.shared

    // MARK: FUNCTION: addPlace
    /// - Description: Inserts a place into Supabase and mirrors it locally in cache.
    /// Called when a user adds a new spot. Also pre-downloads its image for faster loading later.
    func addPlace(_ place: PostPlace) async throws {
        do {
            try await client.from("places").insert(place).execute()
            if let imageString = place.placeImageUrl,
               let url = URL(string: imageString) {
                await cacheMedia(for: [url])
            }
            await cacheStore.upsertPlaces([
                Place(
                    id: place.id,
                    loopID: place.loopID,
                    postedBy: place.postedBy,
                    name: place.name,
                    categoryId: place.categoryId,
                    description: place.description,
                    placeImageUrl: place.placeImageUrl,
                    trailerMediaUrl: place.trailerMediaUrl,
                    createdAt: place.createdAt,
                    locationId: place.locationId,
                    verificationStatus: place.verificationStatus,
                    score: nil,
                    location: nil
                )
            ])
            print(" Inserted place \(place.name)")
        } catch {
            print(" Failed to insert place:", error)
            throw error
        }
    }


    // MARK: FUNCTION: deletePlace
    /// - Description: Deletes a place from Supabase.
    /// Just triggers the remote delete — cache cleanup is handled elsewhere.
    func deletePlace(by id: UUID, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                try await client
                    .from("places")
                    .delete()
                    .eq("place_id", value: id)
                    .execute()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }


    // MARK: FUNCTION: getPlace
    /// - Description: Gets a specific place by its ID.
    /// Checks cache first, then fetches from Supabase if needed.
    func getPlace(by id: UUID) async throws -> Place? {
        if let cached = cacheStore.fetchPlace(id: id) {
            return cached
        }

        let response: [Place] = try await client
            .from("places")
            .select("*, locations:location_id (*)")
            .eq("place_id", value: id)
            .limit(1)
            .execute()
            .value

        guard let place = response.first else { return nil }
        if let imageString = place.placeImageUrl,
           let url = URL(string: imageString) {
            await cacheMedia(for: [url])
        }
        await cacheStore.upsertPlaces([place])
        return place
    }


    // MARK: FUNCTION: getPlaces
    /// - Description: Loads all places for a given loop, with cache fallback.
    /// Returns cached data first, then updates it in background once fresh data arrives.
    func getPlaces(forLoop loopID: UUID, completion: @escaping (Result<[Place], Error>) -> Void) {
        let cached = cacheStore.fetchPlaces(loopID: loopID)
        if !cached.isEmpty {
            completion(.success(cached))
        }

        Task {
            do {
                let places: [Place] = try await client
                    .from("places")
                    .select("*, locations:location_id (*)")
                    .eq("loop_id", value: loopID)
                    .order("created_at", ascending: false)
                    .execute()
                    .value

                await cacheMedia(for: places.compactMap { $0.placeImageUrl }.compactMap(URL.init(string:)))
                await cacheStore.upsertPlaces(places)
                completion(.success(places))
            } catch {
                if cached.isEmpty {
                    completion(.failure(error))
                }
            }
        }
    }


    // MARK: FUNCTION: getPlacesNearby
    /// - Description: Finds nearby places using PostGIS proximity queries.
    /// Runs raw SQL via an RPC and caches results for offline use.
    func getPlacesNearby(latitude: Double, longitude: Double, radiusMeters: Double, completion: @escaping (Result<[Place], Error>) -> Void) {
        Task {
            do {
                let query = """
                select * from places
                where ST_DWithin(
                    geography(ST_MakePoint(longitude, latitude)),
                    geography(ST_MakePoint(\(longitude), \(latitude))),
                    \(radiusMeters)
                )
                order by created_at desc
                """

                let places: [Place] = try await client
                    .rpc("exec_sql", params: ["query": query])
                    .execute()
                    .value

                await cacheMedia(for: places.compactMap { $0.placeImageUrl }.compactMap(URL.init(string:)))
                await cacheStore.upsertPlaces(places)
                completion(.success(places))
            } catch {
                completion(.failure(error))
            }
        }
    }


    // MARK: FUNCTION: getPlaceIdByName
    /// - Description: Checks if a place already exists by name.
    /// Helps prevent duplicates when adding new ones.
    func getPlaceIdByName(_ name: String) async throws -> UUID? {
        let results: [Place] = try await client
            .from("places")
            .select()
            .eq("name", value: name)
            .limit(1)
            .execute()
            .value
        return results.first?.id
    }


    // MARK: FUNCTION: searchPlacesByName
    /// - Description: Searches places by name using Supabase RPC.
    /// Tries cache first, then remote. Also preloads images.
    func searchPlacesByName(_ query: String) async throws -> [Place] {
        let cachedMatches = cacheStore
            .fetchPlaces(loopID: nil)
            .filter { $0.name.localizedCaseInsensitiveContains(query) }

        if !cachedMatches.isEmpty {
            return cachedMatches
        }

        let response: [Place] = try await client
            .rpc("search_places", params: ["query": query])
            .execute()
            .value

        await cacheMedia(for: response.compactMap { $0.placeImageUrl }.compactMap(URL.init(string:)))
        await cacheStore.upsertPlaces(response)
        return response
    }


    // MARK: FUNCTION: refreshPlaces
    /// - Description: Forces a fresh fetch of all loop places from Supabase.
    /// Updates cache afterward. Used in manual refresh flows.
    func refreshPlaces(forLoop loopID: UUID) async throws -> [Place] {
        let places: [Place] = try await client
            .from("places")
            .select("*, locations:location_id (*)")
            .eq("loop_id", value: loopID)
            .order("created_at", ascending: false)
            .execute()
            .value

        await cacheMedia(for: places.compactMap { $0.placeImageUrl }.compactMap(URL.init(string:)))
        await cacheStore.upsertPlaces(places)
        return places
    }


    // MARK: FUNCTION: checkNearbyPlaces
    /// - Description: RPC wrapper to check if any known places exist near given coordinates.
    /// Returns matches and caches them.
    func checkNearbyPlaces(lat: Double, lon: Double, radiusMeters: Double) async throws -> [Place] {
        print("""
         [PlacesRepository.checkNearbyPlaces]
        ├─ Input: lat=\(lat), lon=\(lon), radius=\(radiusMeters)m
        """)

        do {
            let result: [Place] = try await client
                .rpc("check_nearby_places", params: [
                    "p_lat": lat,
                    "p_lon": lon,
                    "p_radius_meters": radiusMeters
                ])
                .execute()
                .value

            await cacheMedia(for: result.compactMap { $0.placeImageUrl }.compactMap(URL.init(string:)))
            await cacheStore.upsertPlaces(result)
            print(" [PlacesRepository.checkNearbyPlaces] Done. Returned \(result.count) place(s).")
            return result
        } catch {
            print(" [PlacesRepository.checkNearbyPlaces] Error: \(error.localizedDescription)")
            throw error
        }
    }


    // MARK: Helper: cacheMedia
    /// - Description: Downloads and stores media files locally.
    /// Called before caching places to make sure their images are available offline.
    private func cacheMedia(for urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls where shouldDownload(url: url) {
                group.addTask { await self.downloadAndCache(url: url) }
            }
        }
    }


    // MARK: Helper: shouldDownload
    /// - Description: Checks if the media is already cached or not.
    private func shouldDownload(url: URL) -> Bool {
        guard url.scheme != "file" else { return false }
        return MediaCache.shared.localURL(forRemoteURL: url) == nil
    }


    // MARK: Helper: downloadAndCache
    /// - Description: Fetches image data and stores it in MediaCache.
    /// Silently skips if already cached.
    private func downloadAndCache(url: URL) async {
        guard shouldDownload(url: url) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            _ = MediaCache.shared.store(data: data, for: url)
        } catch {
            print(" Media cache download failed for \(url): \(error.localizedDescription)")
        }
    }
}
