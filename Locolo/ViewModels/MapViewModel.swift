//
//  MapViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 6/11/2025.
//

import Foundation
import MapKit
import Supabase

@MainActor
final class MapViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var assets: [DigitalAsset] = []
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: -33.865143, longitude: 151.209900),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var zoomLevel: Double = 10

    private let client = SupabaseManager.shared.client
    private let locationManager = CLLocationManager()
    private var fetchTask: Task<Void, Never>? // Track current fetch task

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Request Location
    /// Handles requesting user location permission and starts updates if allowed.
    /// Discussion: Prompts once if permission hasn't been granted yet.
    /// Uses requestLocation() for one-time location instead of continuous updates to prevent excessive API calls.
    func requestLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) {
            // Use requestLocation() for one-time location instead of continuous updates
            locationManager.requestLocation()
        } else {
            errorMessage = "Location access denied."
        }
    }
    
    
    
    // MARK: - Location Updates
    /// Delegate callback triggered when the device provides new location data.
    /// Discussion: Updates map center but doesn't trigger fetch - let zoom/pan handle it.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print(" User location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        
        // Update region but don't trigger fetch here - let zoom/pan handle it
        region.center = location.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(" Location error: \(error.localizedDescription)")
        errorMessage = "Failed to get location: \(error.localizedDescription)"
    }
    
    

    // MARK: - Fetch Assets (Radius scales with zoom)
    /// Fetches nearby digital assets from Supabase within a radius that scales with the map zoom level.
    /// Discussion: Uses a database function `get_nearby_assets` to query assets efficiently.
    /// Here I am just calling the rpc technically through the get nearby assets function
    /// that is using the postgis to query and return the nearbu assets
    /// - Parameters:
    ///   - region: The visible map region to query around.
    ///   - zoomLevel: The current zoom level, used to adjust the search radius.
    func fetchAssetsFor(region: MKCoordinateRegion, zoomLevel: Double) async {
        // Cancel previous fetch if still running
        fetchTask?.cancel()
        
        fetchTask = Task {
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            isLoading = true
            errorMessage = nil
            self.zoomLevel = zoomLevel

            // Validate region to prevent crashes
            guard region.span.longitudeDelta > 0.0001,
                  region.center.latitude.isFinite,
                  region.center.longitude.isFinite else {
                print("⚠️ Invalid region - skipping fetch")
                isLoading = false
                return
            }

            // Estimate visible map width in meters using latitude correction
            let visibleWidthMeters =
                region.span.longitudeDelta * 111_000 * cos(region.center.latitude * .pi / 180)

            // Half of visible width = query radius (but at least 500m)
            let radiusMeters = max(500, visibleWidthMeters / 2)
            print(" Zoom=\(zoomLevel.rounded()), Visible width=\(Int(visibleWidthMeters))m, Radius=\(Int(radiusMeters))m")

            do {
                let rows: [DigitalAsset] = try await client
                    .rpc("get_nearby_assets", params: [
                        "p_lat": region.center.latitude,
                        "p_lon": region.center.longitude,
                        "p_radius_meters": radiusMeters
                    ])
                    .execute()
                    .value

                // Check if task was cancelled before updating
                guard !Task.isCancelled else { return }

                // filter out invalid coordinates before rendering
                self.assets = rows.filter { $0.latitude != nil && $0.longitude != nil }
                print(" Loaded \(self.assets.count) assets within radius \(Int(radiusMeters))m")

            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = error.localizedDescription
                print(" Error fetching assets: \(error.localizedDescription)")
            }

            isLoading = false
        }
        
        await fetchTask?.value
    }
    
}

