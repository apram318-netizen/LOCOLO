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
    private let activeUploadInterval: TimeInterval = 5    // seconds when moving
    private let idleUploadInterval: TimeInterval = 60     // seconds when idle

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
        
        if now.timeIntervalSince(lastSent) >= interval {
            lastSent = now
            print(" Got location update:", loc.coordinate, "speed:", loc.speed)
            LocationUploader.shared.uploadPing(loc)
            LocationManager.shared.userLocation  = loc.coordinate
        }
    }

    
    // MARK: - Simple Distance Utility (auto-uses fresh location or fallback)
    // Using the exact location because I needed something a bit more accurate here.
    func relativeDistance(to assetLat: Double, _ assetLon: Double) -> String {
        let assetLoc = CLLocation(latitude: assetLat, longitude: assetLon)
        
        //  Try fresh immediate location (requestLocation)
        var freshestCoord: CLLocationCoordinate2D?
        let semaphore = DispatchSemaphore(value: 0)
        
        manager.requestLocation()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {   // small wait for fresh result
            freshestCoord = self.userLocation
            semaphore.signal()
        }
        
        semaphore.wait()
        
        //  If still no fresh coordinate, fallback to stored ones
        let coord = freshestCoord
            ?? userLocation
            ?? latestStoredLocation
        
        guard let coord else { return "--" }// HOpe I barely have to see this empty string
        
        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let meters = userLoc.distance(from: assetLoc)
        
        //  Format readable distance
        if meters < 100 {
            return "\(Int(meters)) m"
        } else if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else if meters < 20000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.1f miles", meters / 1609.34)
        }
    }

    
    // MARK: - Delegate: Visits
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        LocationUploader.shared.uploadVisit(visit)
    }
}

