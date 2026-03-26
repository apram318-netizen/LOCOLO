//
//  LocationsRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import CoreLocation
import Foundation
import Supabase

/// Talks directly to Supabase RPCs and the LocationUploader for background updates.
class LocationsRepository {
    private let client = SupabaseManager.shared.client
    private var storedLocations: [Location] = []
    private let uploader = LocationUploader.shared
    
    
    
    
    // MARK: FUNCTION: searchLocations
    /// - Description: Searches locations by name or text query, optionally using the user’s coordinates
    ///   for better ranking. Calls the Supabase RPC of  search_location .
    ///
    ///Using a custom any encodable for functions here because there was some issue with encoding to RPC with the current values as it is
    ///In the Rpc I am using postgis to search for the locations
    ///
    /// - Parameters:
    ///   - query: What user typed in search
    ///   - lat/lon: Optional coordinates to prioritize nearby places
    ///   - maxResults: Limit how many to fetch
    /// - Returns: A list of matching `Location`s
    func searchLocations(
        query: String,
        lat: Double? = nil,
        lon: Double? = nil,
        maxResults: Int = 5
    ) async throws -> [Location] {
        
        let params: [String: AnyEncodable] = [
            "q": AnyEncodable(query),
            "p_lat": AnyEncodable(lat ?? 0),
            "p_lon": AnyEncodable(lon ?? 0),
            "max_results": AnyEncodable(maxResults)
        ]
        
        let response: [Location] = try await client
            .rpc("search_locations", params: params)
            .execute()
            .value
        
        return response
    }
    
    
    
    // MARK: Upload helpers
    /// Just forwards the ping to the shared uploader
    func uploadPing(_ location: CLLocation) {
        uploader.uploadPing(location)
    }

    /// Same idea but for visits (CLVisit objects)
    func uploadVisit(_ visit: CLVisit) {
        uploader.uploadVisit(visit)
    }

    /// Reconciles residency data if needed, runs async in background
    func reconcileResidencyIfNeeded() async {
        await uploader.reconcileIfNeeded()
    }
    
    
    
    // MARK: FUNCTION: insertLocation
    /// - Description: Inserts or upserts a Google place into the database by calling `upsert_location_from_google`.
    /// Basically converts a Google Place into a Supabase `Location` entry.
    ///
    ///Using any encodable for functions here because there was some issue with encoding to RPC with the current struct
    ///
    /// You even left a note to yourself about needing to handle geom differently later — valid.
    func insertLocation(from place: GooglePlacesService.GooglePlace) async throws -> Location {
        let params: [String: AnyEncodable] = [
            "p_google_place_id": AnyEncodable(place.id),
            "p_address": AnyEncodable(place.address),
            "p_name": AnyEncodable(place.name),
            "p_city": AnyEncodable(place.city ?? ""),
            "p_lat": AnyEncodable(place.lat),
            "p_lon": AnyEncodable(place.lon)
        ]
        
        let response: Location = try await client
            .rpc("upsert_location_from_google", params: params)
            .execute()
            .value
        return response
    }
    
    
    
    // MARK: FUNCTION: getLocation
    /// - Description: Gets a single location from Supabase by its UUID.
    /// Just a simple query using `.eq("location_id", value: id)`.
    func getLocation(by id: UUID) async throws -> Location? {
        let response: [Location] = try await client
            .from("locations")
            .select("*")
            .eq("location_id", value: id)
            .limit(1)
            .execute()
            .value
        return response.first
    }
    
    
    
    
    // MARK: FUNCTION: createLocation
    /// - Description: Creates a new location manually (not from Google).
    /// Builds a geometry string from lat/lon for Supabase PostGIS insertion.
    func createLocation(location: Location) async throws -> Location {
        let insertPayload = InsertLocation(
            name: location.name,
            address: location.address,
            city: location.city,
            country: location.country,
            geom: (location.latitude != nil && location.longitude != nil)
                ? "SRID=4326;POINT(\(location.longitude!) \(location.latitude!))"
                : nil
        )

        let response: [Location] = try await client
            .from("locations")
            .insert(insertPayload, returning: .representation)
            .execute()
            .value

        guard let inserted = response.first else {
            throw NSError(
                domain: "LocationsRepository",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No location returned after insert"]
            )
        }
        return inserted
    }
}



struct AnyEncodable: Encodable, Sendable {
    
    private let encodeFunc: (Encoder) throws -> Void
    
    init<T: Encodable & Sendable>(_ value: T) {
        encodeFunc = value.encode
    }
    
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}


struct InsertLocation: Encodable {
    let name: String
    let address: String
    let city: String?
    let country: String?
    let google_place_id: String? = nil
    let geom: String?
}
