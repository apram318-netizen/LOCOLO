//
//  LocationManager.swift
//  Locolo
//
//  Created by Apramjot Singh on 24/9/2025.
//

import Foundation
import CoreLocation
import Combine
import FirebaseFirestore

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // MARK: - Singleton
    static let shared = LocationManager()

    // MARK: - Published properties
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var isMoving: Bool = false
    
    
    var latestStoredLocation: CLLocationCoordinate2D? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "latestUserLocation") as? [String: Any],
              let lat = dict["lat"] as? Double,
              let lon = dict["lon"] as? Double else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Private variables
    private let manager = CLLocationManager()
    private var lastSent: Date = .distantPast
    /// Upload cadence. These were 5 s / 60 s, which meant up to 12 network
    /// round trips a minute while walking (each one writing Firestore twice and
    /// running a nearby-places query). 60 s / 300 s keeps loop-residency maths
    /// accurate while cutting ping volume by ~12x. (Visits + significant-change
    /// monitoring still catch real movement between pings.)
    private let activeUploadInterval: TimeInterval = 60    // seconds when moving
    private let idleUploadInterval: TimeInterval = 300     // seconds when idle
    /// Skip uploads when the user has barely moved, regardless of timer.
    private let minUploadDistanceMeters: CLLocationDistance = 25
    private var lastUploadedLocation: CLLocation?

    // MARK: - Init
    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10   // 10 m update trigger I can changeit later depending o functionality and battery results
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        requestPermission()
    }

    /// Background AR mode: keep precise updates flowing with the screen off
    /// (no auto-pause) and show the blue location pill so it's never hidden.
    func setBackgroundExploring(_ on: Bool) {
        manager.pausesLocationUpdatesAutomatically = !on
        manager.showsBackgroundLocationIndicator = on
        manager.distanceFilter = on ? 5 : 10
        if on {
            if manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestAlwaysAuthorization()
            }
            manager.startUpdatingLocation()
        }
    }

    // MARK: - Permissions
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestAlwaysAuthorization()
        }
    }

    // MARK: - Tracking control
    /// - Description: It starts the user location track , if app is not running will start when 500 m movement is there
    ///
    ///  Called after getting authorization currently, or whenever the app launches
    func startTracking() {
        print(" Starting full location tracking…")
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
    }
    

    // MARK: - Tracking control
    /// - Description: it stops the tracking, generally called when we found a  location
    /// -Used in: Currently not used anywhere but can be used when we want to stop tracking
    func stopTracking() {
        print(" Stopping location tracking.")
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
    }

    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
    
    // MARK: - Delegate: Authorization
    
    // MARK: - Function: locationManager(_:didChangeAuthorization:)
    /// - Description: it is managing the different states of users location permissions
    /// - Parameters: manager: CLLocationManager, status: CLAuthorizationStatus
    /// - Returns: Nothing
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            startTracking()
        case .authorizedWhenInUse:
            // trying to use Always for background tracking
            manager.requestAlwaysAuthorization()
        case .restricted, .denied:
            print(" Location access denied by user... ughhh, Not my loss tho ")
        default:
            break
        }
    }

    // MARK: - Delegate: Updates
    
    // MARK: - Function: locationManager(_:didUpdateLocations:)
    /// - Description: it is getting the location updates from the CLLocationManager and uploading them based on certain conditions
    /// - Parameters: manager: CLLocationManager, locations: [CLLocation]
    /// - Returns: Nothing
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= 100 else { return }

        userLocation = loc.coordinate
        isMoving = loc.speed > 0.5  // ~1.8 km/h if I tried to calculate..

        let now = Date()
        let interval = isMoving ? activeUploadInterval : idleUploadInterval
        guard now.timeIntervalSince(lastSent) >= interval else { return }

        // Distance gate: standing still (GPS jitter) shouldn't burn an upload.
        if let last = lastUploadedLocation,
           loc.distance(from: last) < minUploadDistanceMeters {
            return
        }

        lastSent = now
        lastUploadedLocation = loc
        LocationUploader.shared.uploadPing(loc)
    }

    
    // MARK: - Simple Distance Utility
    /// Distance from the user's last known position to a coordinate.
    ///
    /// The previous implementation called `requestLocation()` and then
    /// **blocked the calling thread on a semaphore for 300 ms** waiting for a
    /// fix. Called from a SwiftUI body (e.g. per row in a list) that froze the
    /// main thread. It is now a pure, non-blocking read of the cached location.
    func relativeDistance(to assetLat: Double, _ assetLon: Double) -> String {
        guard let coord = userLocation ?? latestStoredLocation else { return "--" }

        let meters = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: assetLat, longitude: assetLon))

        if meters < 1000 {
            return "\(Int(meters)) m"
        } else if meters < 20000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f km", meters / 1000)
        }
    }

    
    // MARK: - Delegate: Visits
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        LocationUploader.shared.uploadVisit(visit)
    }
}

