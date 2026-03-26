//
//  LocationViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 22/9/2025.
//

import CoreLocation
import Foundation
import Combine

@MainActor
class LocationViewModel: ObservableObject {
    
    @Published var locations: [Location] = []                // Search results or saved locations
    @Published var selectedLocation: Location?               // The location the user selects
    @Published var isLoading: Bool = false                   // Loading indicator for async calls
    @Published var errorMessage: String?                     // Holds any error message for UI
    
    private let repo = LocationsRepository()
    
    // MARK: - Location Search Flow ---- Not in use currently
    /// - Description: Handles full location search logic — tries Supabase first, then Google Places fallback.
    /// - Parameters:
    ///   - query: The search term entered by the user.
    func searchLocationFlow(query: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            
            let dbResults = try await repo.searchLocations(query: query)
            if !dbResults.isEmpty {
                locations = dbResults
                return
            }
            
            let googleResults = try await GooglePlacesService.shared.searchPlaces(query: query)
            if let first = googleResults.first {
                let inserted = try await repo.insertLocation(from: first)
                locations = [inserted]
                selectedLocation = inserted
                return
            }
            
            errorMessage = "Not found in DB or Google. Let user add manually and drop pin."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    
    // MARK: - Add New Location
    /// - Description: Inserts a new location manually into the Supabase DB.
    /// - Parameters:
    ///   - location: The Location object to insert.
    /// - Returns: The inserted Location returned from the supabase.
    /// - Discussion:
    ///   it is currently being used when user adds a new custom place.
    ///   Future improvement: I need toimplement auto-check for duplicates using geospatial comparison.-- Possibly I can use a trigger on supabase
    func addLocation(_ location: Location) async throws -> Location {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let inserted = try await repo.createLocation(location: location)
            return inserted
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    
    
    // MARK: - Location Tracking Properties
    
    @Published var currentLocation: CLLocationCoordinate2D?  // Latest GPS coordinates
    @Published var isTracking: Bool = false                  // Whether tracking is currently active
    @Published var lastUploadTime: Date?                     // Timestamp of last uploaded ping
    @Published var lastError: String?                        // Error logs for debug or display
    
    private var cancellables = Set<AnyCancellable>()
    private let locationManager = LocationManager.shared
    private let uploader = LocationUploader.shared
    
    
    

    /// Ensures the view model always has access to the most recent location.
    /// Could later include accuracy thresholds to avoid noisy GPS updates and flooding my firebase
    init() {
        bindToLocationUpdates()
    }
    
    // MARK: FUNCTION: bindToLocationUpdates
    /// - Description: uses the shared `LocationManager`'s published location updates.
    /// - Discussion:
    ///  Keeps `currentLocation` in sync in real-time just by updating the user location
    private func bindToLocationUpdates() {
        locationManager.$userLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.currentLocation = location
            }
            .store(in: &cancellables)
    }
    
    
    
    
    // MARK: - Tracking Control
    /// - Description: Starts background tracking through `LocationManager`.
    func startTracking() {
        locationManager.startTracking()
        isTracking = true
    }
    
    
    /// - Description: Stops background tracking and updates UI state.
    func stopTracking() {
        locationManager.stopTracking()
        isTracking = false
    }
    
    
    
    // MARK: - Residency and Manual Pings
    /// - Description: Forces reconciliation of user residency state via the uploader.
    /// - Discussion:
    ///   • Usually runs in the background, but can be triggered manually for debugging or sync.
    func reconcileResidencyIfNeeded() async {
        do {
            await uploader.reconcileIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }
    
    
    
    /// - Description: Manually uploads a single ping (used for debugging/testing).
    /// - Discussion:
    ///  Helpful for manual triggers or dev UI buttons.
    ///  Could log results into a local cache for later speed in diagnostics it takes ages to reconcile currently .
    func uploadManualPing() {
        guard let loc = locationManager.userLocation else {
            lastError = "No location available."
            return
        }
        let cl = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
        uploader.uploadPing(cl)
        lastUploadTime = Date()
    }
    
    
}
