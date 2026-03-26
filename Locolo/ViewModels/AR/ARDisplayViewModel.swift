//
//  ARDisplayViewModel.swift
//  Locolo
//
//  This file controls AR GeoTracking, GPS, and RealityKit placement.
//  It runs location updates, checks AR support, starts the AR session,
//  listens for tracking status, loads assets from Supabase,
//  and places all 3D models at real world coordinates.
//

import Foundation
import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import Combine

@MainActor
class ARDisplayViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, ARSessionDelegate {

    // MARK: Published user state
    @Published var statusMessage: String?
    @Published var userLocation: CLLocation?
    @Published var isLocalized = false
    @Published var nearbyAssets: [DigitalAsset] = []

    // Tracks placed asset ids
    private var placedIds = Set<UUID>()

    private var cancellables = Set<AnyCancellable>()

    // MARK: Internal system objects
    var arView: ARView?
    let locationManager = CLLocationManager()


    // MARK: Init
    override init() {
        super.init()
        locationManager.delegate = self
    }


    // MARK: Ask for location permission and start GPS
    /// - Description: Requests permission and starts GPS updates. Needed before AR GeoTracking can work.
    func startLocationUpdates() {
        statusMessage = "Requesting location permission"

        switch locationManager.authorizationStatus {

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            statusMessage = "Location permission denied"

        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.startUpdatingLocation()

        @unknown default:
            break
        }
    }


    // MARK: Location delegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            statusMessage = "Finding your location"
            manager.startUpdatingLocation()
        }
    }

    
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "Location error: \(error.localizedDescription)"
    }

    
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        userLocation = loc

        if !isLocalized && arView?.session.configuration == nil {
            statusMessage = "Location found. Checking AR support"
            checkGeoTrackingSupport()
        }
    }


    // MARK: Check AR GeoTracking support
    /// - Description: Checks if this device and region support GeoTracking.
    func checkGeoTrackingSupport() {
        guard ARGeoTrackingConfiguration.isSupported else {
            statusMessage = "GeoTracking not supported"
            return
        }

        statusMessage = "Checking AR availability here"

        ARGeoTrackingConfiguration.checkAvailability { [weak self] available, error in
            guard let self = self else { return }

            if let error = error {
                self.statusMessage = "AR not available: \(error.localizedDescription)"
                return
            }

            if !available {
                self.statusMessage = "GeoTracking not available in this area"
                return
            }

            self.startARSession()
        }
    }

    

    // MARK: Start AR session
    /// - Description: Creates and runs the geotracking session. Resets tracking to avoid old state.
    func startARSession() {
        guard let arView = arView else { return }

        cancellables.removeAll()

        let config = ARGeoTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        statusMessage = "Starting AR session"

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = self
    }


    // MARK: Tracking status updates
    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {

        switch geoTrackingStatus.accuracy {
        case .high:
            statusMessage = "High accuracy"
        case .medium:
            statusMessage = "Medium accuracy"
        case .low:
            statusMessage = "Low accuracy"
        @unknown default:
            break
        }

        switch geoTrackingStatus.state {

        case .localized:
            if !isLocalized {
                isLocalized = true
                statusMessage = "Localized. Loading assets"

                Task {
                    await fetchNearbyAssets()
                    placeAllAssetsIfLocalized()
                }
            }

        case .initializing:
            statusMessage = "Initializing AR"

        case .localizing:
            statusMessage = "Localizing. Move around"

        case .notAvailable:
            statusMessage = "Not available here"

        @unknown default:
            statusMessage = "Searching"
        }
    }


    // MARK: Reset AR state
    /// - Description: Clears local tracking and resets placement state.
    func resetARState() {
        userLocation = nil
        isLocalized = false
        nearbyAssets = []
        placedIds.removeAll()
        statusMessage = "Finding location"
    }

    
    func session(_ session: ARSession, didFailWithError error: Error) {
        statusMessage = "AR failed: \(error.localizedDescription)"
    }


    // MARK: Fetch assets from RPC
    /// - Description: Calls the Supabase function get_nearby_assets_full to load assets near the user.
    func fetchNearbyAssets(radiusMeters: Double = 200) async {
        guard let loc = userLocation else {
            statusMessage = "No location"
            return
        }

        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude

        do {
            let assets: [DigitalAsset] = try await SupabaseManager.shared.client
                .rpc("get_nearby_assets_full", params: [
                    "p_lat": lat,
                    "p_lon": lon,
                    "p_radius_meters": radiusMeters
                ])
                .execute()
                .value

            await MainActor.run {
                nearbyAssets = assets
                statusMessage = "Loaded \(assets.count) assets"
            }

        } catch {
            await MainActor.run {
                statusMessage = "Failed to load assets"
            }
        }
    }


    
    // MARK: Place a single model
    /// - Description: Downloads the model, loads it with RealityKit, sets scale and rotation, and attaches it to a geo anchor.
    func placeAsset(
        _ asset: DigitalAsset,
        in arView: ARView,
        cameraTransform: simd_float4x4?
    ) {

        if placedIds.contains(asset.id) { return }
        placedIds.insert(asset.id)

        guard
            let lat = asset.latitude,
            let lon = asset.longitude,
            let url = URL(string: asset.fileUrl)
        else { return }

        let altitude = userLocation?.altitude ?? 0
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        #if targetEnvironment(simulator)
        print("Simulator cannot place geo anchors")
        return
        #else

        let geoAnchor = ARGeoAnchor(name: asset.name ?? "", coordinate: coord, altitude: altitude)
        arView.session.add(anchor: geoAnchor)

        let anchorEntity = AnchorEntity(anchor: geoAnchor)
        #endif


        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let http = response as? HTTPURLResponse, http.statusCode != 200 { return }

                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".usdz")
                try data.write(to: temp)

                let request = Entity.loadAsync(contentsOf: temp)

                request
                    .sink(receiveCompletion: { c in
                        if case let .failure(error) = c {
                            print("Load error", error)
                        }
                    }, receiveValue: { [weak self] entity in
                        guard let self = self else { return }

                        let sx = Float(asset.scaleX ?? 1)
                        let sy = Float(asset.scaleY ?? 1)
                        let sz = Float(asset.scaleZ ?? 1)
                        entity.scale = [sx, sy, sz]

                        let rx = Float(asset.rotationX ?? 0) * .pi / 180
                        let ry = Float(asset.rotationY ?? 0) * .pi / 180
                        let rz = Float(asset.rotationZ ?? 0) * .pi / 180

                        let rotX = simd_quatf(angle: rx, axis: [1, 0, 0])
                        let rotY = simd_quatf(angle: ry, axis: [0, 1, 0])
                        let rotZ = simd_quatf(angle: rz, axis: [0, 0, 1])

                        entity.transform.rotation = rotZ * rotY * rotX

                        #if !targetEnvironment(simulator)
                        anchorEntity.addChild(entity)
                        arView.scene.addAnchor(anchorEntity)
                        #endif

                        self.statusMessage = "Placed \(asset.name ?? "asset")"
                    })
                    .store(in: &cancellables)

            } catch {
                print("Download error:", error)
            }
        }
    }


    
    // MARK: Place all nearby assets
    /// - Description: Loops through all loaded assets and places them when GeoTracking is ready.
    func placeAllAssetsIfLocalized() {
        guard let arView = arView else { return }

        #if targetEnvironment(simulator)
        print("Simulator skip")
        return
        #endif

        let cam = arView.session.currentFrame?.camera.transform

        for asset in nearbyAssets {
            placeAsset(asset, in: arView, cameraTransform: cam)
        }
    }


    // MARK: Manual test helper
    /// - Description: Places a test geo anchor at a coordinate.
    func placeGeoAnchorIfSupported(_ coordinate: CLLocationCoordinate2D) async {
        #if targetEnvironment(simulator)
        print("Simulator skip")
        return
        #else
        do {
            let anchor = try await ARGeoAnchor(coordinate: coordinate)
            let entity = AnchorEntity(anchor: anchor)
            arView?.scene.addAnchor(entity)
        } catch {
            print("Geo anchor error", error)
        }
        #endif
    }
}


//  Main resources used in this file:
//  Apple AR GeoTracking
//  https://developer.apple.com/documentation/arkit/argeotrackingconfiguration
//
//  Apple Geo Anchors
//  https://developer.apple.com/documentation/arkit/argeoanchor
//
//  RealityKit async model loading
//  https://developer.apple.com/documentation/realitykit/entity/loadasync
//
// https://youtu.be/-uhCNRMDDVg?si=Oo0mceDPAjgiEZ8B
//
// https://youtu.be/hHSbMkhruOg?si=Q1oY_Lfl_9Jg_wn5


