//
//  ARDisplayViewModel.swift
//  Locolo
//
//  This file controls AR asset placement, GPS, and RealityKit rendering.
//  It supports two placement modes so the viewer works *everywhere*:
//
//    1. GeoTracking mode  — Apple's ARGeoTrackingConfiguration. Most
//       accurate, but only available in cities Apple has mapped.
//    2. GPS / World mode  — ARWorldTrackingConfiguration with a
//       gravity+heading aligned world. Assets are placed by computing
//       each one's bearing and distance from the user, so this works
//       anywhere with a GPS fix and a compass.
//
//  We prefer GeoTracking when it's available and localizes quickly, and
//  fall back to GPS mode otherwise (unsupported region, unavailable
//  area, or GeoTracking that just won't localize in time).
//

import Foundation
import SwiftUI
import RealityKit
import ARKit
import CoreLocation
import Combine

@MainActor
class ARDisplayViewModel: NSObject, ObservableObject, CLLocationManagerDelegate, ARSessionDelegate {

    // MARK: Placement mode
    enum TrackingMode {
        case geo     // ARGeoTrackingConfiguration (geo-anchored)
        case world   // ARWorldTrackingConfiguration (GPS + heading placement)
    }

    // MARK: Published user state
    @Published var statusMessage: String?
    @Published var userLocation: CLLocation?
    @Published var isLocalized = false
    @Published var trackingMode: TrackingMode = .geo
    @Published var nearbyAssets: [DigitalAsset] = []
    @Published var listeningHint: String?
    /// Transient caption shown when an asset's trigger fires ("✨ … came to life").
    @Published var triggerFlash: String?

    /// Device compass heading in degrees (true north), for the AR radar.
    @Published var headingDegrees: Double?

    /// Set when camera or location permission is denied, so the view can offer
    /// an "Open Settings" path instead of a dead end. (WS3)
    @Published var permissionDenied = false
    /// Set when we can't get going (no GPS fix, etc.) and a manual retry helps. (WS3)
    @Published var showRetry = false

    // MARK: Hot/cold finder (logic in ARDisplayViewModel+Finder.swift)
    @Published var finderTrend: FinderTrend = .steady
    /// Set briefly when the user walks up to an asset for the first time.
    @Published var justFound: DigitalAsset?
    var finderLastDistance: Double?
    var finderLastTargetId: UUID?

    /// Where we last fetched assets from; when the user walks past
    /// `refetchDistanceMeters` we reload so newly-nearby assets appear. (WS3)
    private var lastFetchOrigin: CLLocation?
    private let refetchDistanceMeters: Double = 75
    private var lastFailedFetchRetry = Date.distantPast
    /// Fires if no GPS fix arrives shortly after we start, to surface a retry. (WS3)
    private var noFixTask: Task<Void, Never>?

    /// Human-readable badge for the active placement mode, shown once ready.
    var trackingModeLabel: String {
        switch trackingMode {
        case .geo:   return "Geo-anchored"
        case .world: return "GPS mode"
        }
    }

    /// True once ARKit confirmed geo-tracking data exists here, which is when
    /// a manual Geo ⇄ GPS switch is meaningful.
    @Published private(set) var geoAvailableHere = false
    private static let prefersGPSModeKey = "ar.prefersGPSMode"
    private var prefersGPSMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.prefersGPSModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.prefersGPSModeKey) }
    }

    /// Camera position (world space) that corresponds to `worldOriginLocation`.
    /// Zero at session start; moved on re-anchor so GPS-mode placement is
    /// measured from a recent fix instead of drifting from the session start.
    private var worldOriginCameraOffset = SIMD3<Float>(repeating: 0)
    private var worldAnchors: [UUID: (anchor: AnchorEntity, asset: DigitalAsset)] = [:]
    private let reanchorMaxAccuracyMeters: Double = 25

    // Tracks placed asset ids
    private var placedIds = Set<UUID>()

    /// Whether THIS view model has started a session. The ARView is a shared
    /// singleton, so `session.configuration` stays non-nil after the first
    /// visit and can't tell us whether we still need to start one.
    private var hasStartedSession = false

    /// Bumped whenever placed content is cleared. A model load that finishes
    /// after its session was reset carries a stale generation and is dropped,
    /// otherwise it would re-add a dead anchor next to the fresh placement.
    private var placementGeneration = 0

    private var cancellables = Set<AnyCancellable>()

    /// Model-load Combine tokens, kept SEPARATE from `cancellables`. A
    /// geo→world fallback clears `cancellables`, and previously that also
    /// cancelled any USDZ load in flight, stranding half-placed assets. These
    /// tokens survive a mode switch. (WS3.7)
    private var modelLoadTokens = Set<AnyCancellable>()

    /// De-duplicates concurrent downloads of the same USDZ: the first placement
    /// that needs a remote URL owns the download; later placements await the
    /// same task instead of re-fetching the bytes. (WS8)
    private var inFlightDownloads: [URL: Task<URL, Error>] = [:]

    /// Upper bound on entities kept in the scene at once. We place the nearest
    /// N assets and skip the rest so memory stays bounded in dense areas. (WS8)
    private let maxPlacedEntities = 40

    /// The GPS location that corresponds to the AR world origin. In GPS mode
    /// all asset offsets are measured from here, since world anchors are
    /// positioned relative to where the session started, not the live camera.
    private var worldOriginLocation: CLLocation?

    /// If GeoTracking is supported but never localizes, this task flips us to
    /// GPS mode so the user is never left staring at an empty camera.
    private var geoFallbackTask: Task<Void, Never>?
    private let geoFallbackTimeout: UInt64 = 25_000_000_000 // 25s in nanoseconds

    // How far out we still trust GPS/heading placement. Beyond this, small GPS
    // errors turn into large angular errors, so we skip those assets.
    private let maxWorldPlacementMeters: Double = 250

    // MARK: Internal system objects
    var arView: ARView?
    let locationManager = CLLocationManager()

    // Runs the per-asset triggers (tap / proximity / speech / shake)
    let triggerEngine = TriggerEngine()
    private var frameCount = 0


    // MARK: Init
    override init() {
        super.init()
        locationManager.delegate = self
        triggerEngine.onListeningHintChanged = { [weak self] hint in
            self?.listeningHint = hint
        }
        triggerEngine.onPlaybackMessage = { [weak self] message in
            self?.statusMessage = message
        }
        triggerEngine.onTriggerFired = { [weak self] asset in
            self?.triggerFlash = "✨ \(asset.name ?? "Asset") came to life"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self?.triggerFlash?.contains(asset.name ?? "Asset") == true {
                    self?.triggerFlash = nil
                }
            }
        }
    }


    // MARK: Ask for location permission and start GPS
    /// - Description: Requests permission and starts GPS updates. Needed before
    /// either placement mode can work.
    func startLocationUpdates() {
        statusMessage = "Requesting location permission"
        permissionDenied = false
        showRetry = false

        switch locationManager.authorizationStatus {

        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            statusMessage = "Location access is off. Turn it on in Settings to place and see AR here."
            permissionDenied = true

        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()   // drives the AR radar
            armNoFixFallback()

        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // trueHeading is -1 when invalid; fall back to magnetic.
        headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    // MARK: AR radar (bearings to nearby assets)

    struct RadarBlip: Identifiable {
        let id: UUID
        /// Radians clockwise from the direction the device is facing.
        let relativeAngle: Double
        /// 0 (here) … 1 (at/beyond radar range).
        let normalizedDistance: Double
    }

    /// Blips for the radar overlay: each nearby asset's bearing relative to
    /// where the user is facing, distance-scaled into the ring.
    var radarBlips: [RadarBlip] {
        guard let origin = userLocation, let heading = headingDegrees else { return [] }
        let radarRange: Double = 200   // metres represented by the ring's edge
        return nearbyAssets.compactMap { asset in
            guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
            let target = CLLocation(latitude: lat, longitude: lon)
            let distance = origin.distance(from: target)
            let absolute = bearing(from: origin.coordinate,
                                   to: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            let relative = absolute - heading * .pi / 180
            return RadarBlip(
                id: asset.id,
                relativeAngle: relative,
                normalizedDistance: min(distance / radarRange, 1.0)
            )
        }
    }

    /// Manual retry from the recovery UI: restart the whole flow. (WS3)
    func retry() {
        resetARState()
        startLocationUpdates()
    }

    /// If no GPS fix arrives within ~10s, fall back to the last known location
    /// when possible, otherwise surface a retry so the user isn't stuck. (WS3)
    private func armNoFixFallback() {
        noFixTask?.cancel()
        noFixTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, !Task.isCancelled, self.userLocation == nil else { return }
            if let last = self.locationManager.location {
                self.userLocation = last
                self.statusMessage = "Using your last known location"
                if !self.hasStartedSession { self.chooseTrackingMode() }
            } else {
                self.statusMessage = "Couldn't get your location. Check you're outdoors with a clear sky, then retry."
                self.showRetry = true
            }
        }
    }


    // MARK: Location delegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            permissionDenied = false
            statusMessage = "Finding your location"
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
            armNoFixFallback()
        case .denied, .restricted:
            statusMessage = "Location access is off. Turn it on in Settings to place and see AR here."
            permissionDenied = true
        default:
            break
        }
    }


    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusMessage = "Location error: \(error.localizedDescription)"
    }


    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        userLocation = loc
        noFixTask?.cancel()      // we have a fix now
        showRetry = false
        updateFinder()

        // Kick off tracking once, as soon as we have a first fix and no session.
        if !isLocalized && !hasStartedSession {
            statusMessage = "Location found. Checking AR support"
            chooseTrackingMode()
        }

        // Re-fetch as the user walks, so newly-nearby assets appear without a
        // session restart. placedIds prevents re-placing what's already up. (WS3)
        if isLocalized, let origin = lastFetchOrigin, loc.distance(from: origin) > refetchDistanceMeters {
            lastFetchOrigin = loc
            reanchorWorldOrigin()
            Task {
                await fetchNearbyAssets()
                placeAllAssets()
            }
        } else if isLocalized, lastFetchOrigin == nil,
                  Date().timeIntervalSince(lastFailedFetchRetry) > 20 {
            // The first fetch failed (lastFetchOrigin is only set on success),
            // so the walk trigger above could never fire. Retry, throttled.
            lastFailedFetchRetry = Date()
            Task {
                await fetchNearbyAssets()
                placeAllAssets()
            }
        }
    }


    // MARK: Choose a placement mode
    /// - Description: Prefers GeoTracking where it's supported and available;
    /// otherwise starts GPS mode immediately so the viewer still works.
    func chooseTrackingMode() {
        guard ARGeoTrackingConfiguration.isSupported else {
            statusMessage = "Using GPS mode"
            startWorldTrackingSession()
            return
        }

        statusMessage = "Checking AR availability here"

        // The availability callback arrives on a background queue.
        ARGeoTrackingConfiguration.checkAvailability { [weak self] available, error in
            Task { @MainActor in
                guard let self else { return }

                self.geoAvailableHere = error == nil && available
                if !self.geoAvailableHere {
                    // Supported hardware, but no geo data for this area → GPS mode.
                    self.statusMessage = "Using GPS mode"
                    self.startWorldTrackingSession()
                    return
                }

                if self.prefersGPSMode {
                    self.statusMessage = "Using GPS mode (your choice)"
                    self.startWorldTrackingSession()
                    return
                }

                self.startGeoTrackingSession()
            }
        }
    }


    // MARK: Manual mode switch
    /// - Description: Lets the user override the automatic choice, e.g. when
    /// geo-localization keeps failing under trees or GPS mode is jittery. The
    /// choice is remembered for next time.
    func toggleTrackingMode() {
        switch trackingMode {
        case .geo:
            prefersGPSMode = true
            statusMessage = "Switched to GPS mode"
            startWorldTrackingSession()
        case .world:
            guard geoAvailableHere else {
                statusMessage = "Geo-anchoring isn't available here"
                return
            }
            prefersGPSMode = false
            statusMessage = "Switching to geo-anchoring"
            startGeoTrackingSession()
        }
        ARHaptics.tick()
    }


    // MARK: Start GeoTracking session
    /// - Description: Runs the geo-anchored session and arms a timeout that
    /// drops to GPS mode if it never localizes.
    func startGeoTrackingSession() {
        guard let arView = arView else { return }

        cancellables.removeAll()
        hasStartedSession = true
        trackingMode = .geo
        // `.removeExistingAnchors` below drops every geo anchor, so forget the
        // placements too; `.localized` then re-fetches and re-places.
        isLocalized = false
        clearPlacedContent()

        let config = ARGeoTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic   // image-based lighting match
        // People occlusion: assets sit behind passers-by where supported.
        if ARGeoTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        statusMessage = "Starting AR session"
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = self
        enableRealismOptions()

        armGeoFallback()
    }


    /// - Description: If GeoTracking hasn't localized within the timeout, switch
    /// to GPS mode. Cancelled the moment we localize.
    private func armGeoFallback() {
        geoFallbackTask?.cancel()
        geoFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.geoFallbackTimeout ?? 25_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.trackingMode == .geo, !self.isLocalized {
                self.statusMessage = "Couldn't geo-localize. Switching to GPS mode"
                self.startWorldTrackingSession()
            }
        }
    }


    // MARK: Start GPS / World-tracking session
    /// - Description: Runs a gravity+heading aligned world session. With this
    /// alignment ARKit orients the world so -Z is true north and +X is east,
    /// letting us place assets from their GPS bearing and distance.
    func startWorldTrackingSession() {
        guard let arView = arView else { return }

        geoFallbackTask?.cancel()
        cancellables.removeAll()
        hasStartedSession = true
        trackingMode = .world
        isLocalized = false
        clearPlacedContent()
        worldOriginLocation = nil
        worldOriginCameraOffset = .zero

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic   // image-based lighting match
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }
        // LiDAR scene mesh → assets occlude behind real geometry where available.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        statusMessage = "Starting GPS AR. Move your phone to begin"
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = self
        enableRealismOptions()
    }

    /// Turns on RealityKit occlusion rendering when the device supports it.
    /// Safe to call after any session.run; no-op where unsupported.
    private func enableRealismOptions() {
        guard let arView = arView else { return }
        #if !targetEnvironment(simulator)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        #endif
    }


    // MARK: GeoTracking status updates (geo mode only)
    func session(_ session: ARSession, didChange geoTrackingStatus: ARGeoTrackingStatus) {

        switch geoTrackingStatus.accuracy {
        case .high:   statusMessage = "High accuracy"
        case .medium: statusMessage = "Medium accuracy"
        case .low:    statusMessage = "Low accuracy"
        @unknown default: break
        }

        switch geoTrackingStatus.state {

        case .localized:
            if !isLocalized {
                geoFallbackTask?.cancel()
                isLocalized = true
                statusMessage = "Localized. Loading assets"

                Task {
                    await fetchNearbyAssets()
                    placeAllAssets()
                }
            }

        case .initializing:
            statusMessage = "Initializing AR"

        case .localizing:
            statusMessage = "Localizing. Move around"

        case .notAvailable:
            // Region flipped to unavailable mid-session — fall back.
            if trackingMode == .geo, !isLocalized {
                statusMessage = "Geo unavailable here. Switching to GPS mode"
                startWorldTrackingSession()
            }

        @unknown default:
            statusMessage = "Searching"
        }
    }


    // MARK: Reset AR state
    /// - Description: Clears tracking and placement state and tears down the
    /// trigger detectors (mic, motion sensors).
    func resetARState() {
        geoFallbackTask?.cancel()
        noFixTask?.cancel()
        hasStartedSession = false
        userLocation = nil
        isLocalized = false
        trackingMode = .geo
        nearbyAssets = []
        clearPlacedContent()
        worldOriginLocation = nil
        worldOriginCameraOffset = .zero
        geoAvailableHere = false
        lastFetchOrigin = nil
        modelLoadTokens.removeAll()
        inFlightDownloads.removeAll()
        permissionDenied = false
        showRetry = false
        finderTrend = .steady
        finderLastDistance = nil
        finderLastTargetId = nil
        justFound = nil
        statusMessage = "Finding location"
    }

    // MARK: Snapshot
    /// Captures the camera feed with the placed AR content composited in.
    func captureSnapshot() async -> UIImage? {
        guard let arView else { return nil }
        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// - Description: Removes every placed model from the scene and forgets
    /// what was placed. The ARView is a long-lived singleton, so without this
    /// each re-entry (or session re-run) stacks another copy of every asset.
    private func clearPlacedContent() {
        arView?.scene.anchors.removeAll()
        placedIds.removeAll()
        worldAnchors.removeAll()
        placementGeneration += 1
        triggerEngine.teardown()
    }


    // MARK: Frame updates
    /// - Description: In GPS mode, waits for world tracking to stabilize, then
    /// loads and places assets. Also runs proximity triggers (throttled).
    func session(_ session: ARSession, didUpdate frame: ARFrame) {

        // GPS-mode localization: place once the camera is tracking normally.
        if trackingMode == .world, !isLocalized, userLocation != nil,
           case .normal = frame.camera.trackingState {
            worldOriginLocation = userLocation
            isLocalized = true
            statusMessage = "Ready (GPS mode). Loading assets"
            Task {
                await fetchNearbyAssets()
                placeAllAssets()
            }
        }

        frameCount += 1
        guard frameCount % 10 == 0, triggerEngine.hasProximityAssets else { return }

        let transform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(transform.columns.3.x,
                                          transform.columns.3.y,
                                          transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x,
                                    transform.columns.2.y,
                                    transform.columns.2.z)
        triggerEngine.updateProximity(cameraPosition: cameraPosition, cameraForward: forward)
    }


    func session(_ session: ARSession, didFailWithError error: Error) {
        statusMessage = "AR failed: \(error.localizedDescription)"
        // A denied camera surfaces here as an ARKit sensor-unavailable error.
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            permissionDenied = true
            statusMessage = "Camera access is off. Turn it on in Settings to use AR."
        }
    }

    // MARK: Camera tracking quality (WS3)
    /// - Description: Turns ARKit's limited-tracking reasons into short,
    /// actionable hints instead of leaving the user on a frozen scene.
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            // Don't stomp on a more useful message once assets are up.
            if !isLocalized { statusMessage = "Tracking. Look around" }
        case .notAvailable:
            statusMessage = "AR tracking unavailable"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:     statusMessage = "Slow down — moving too fast"
            case .insufficientFeatures: statusMessage = "Point at a more textured area"
            case .initializing:        statusMessage = "Starting AR — move your phone gently"
            case .relocalizing:        statusMessage = "Reconnecting to your surroundings"
            @unknown default:          statusMessage = "Adjusting…"
            }
        }
    }

    // MARK: Interruptions (WS3)
    func sessionWasInterrupted(_ session: ARSession) {
        statusMessage = "AR paused"
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        statusMessage = "Resuming AR"
        // Re-run the appropriate configuration so tracking recovers cleanly.
        switch trackingMode {
        case .geo:   startGeoTrackingSession()
        case .world: startWorldTrackingSession()
        }
    }


    // MARK: Fetch assets from RPC
    /// - Description: Calls get_nearby_assets_full to load assets near the user.
    func fetchNearbyAssets(radiusMeters: Double = 200) async {
        lastFailedFetchRetry = Date()
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

            // Only USDZ models can be placed (photo assets share the table),
            // and blocked/reported content never enters the scene.
            let placeable = assets.filter { $0.fileType.lowercased() == "usdz" }
            nearbyAssets = SafetyService.shared.visible(placeable)
            lastFetchOrigin = loc     // anchor for walk-based re-fetch (WS3)
            let count = nearbyAssets.count
            statusMessage = count == 0
                ? "No AR assets nearby yet"
                : "Loaded \(count) asset\(count == 1 ? "" : "s")"

        } catch {
            statusMessage = "Failed to load assets"
        }
    }


    // MARK: Place all nearby assets
    /// - Description: Dispatches placement based on the active mode.
    func placeAllAssets() {
        guard let arView = arView else { return }

        #if targetEnvironment(simulator)
        LocoloLog.debug(LocoloLog.ar, "simulator skip: AR placement")
        return
        #else
        // Place the nearest assets first and cap the total so memory stays
        // bounded where lots of assets cluster together. (WS8)
        let ordered = nearestAssets(limit: maxPlacedEntities)
        switch trackingMode {
        case .geo:
            let cam = arView.session.currentFrame?.camera.transform
            for asset in ordered {
                placeAssetGeo(asset, in: arView, cameraTransform: cam)
            }
        case .world:
            for asset in ordered {
                placeAssetWorld(asset, in: arView)
            }
        }
        #endif
    }

    /// - Description: `nearbyAssets` ordered nearest-first (from the world
    /// origin, else the live location) and capped to `limit`. (WS8)
    private func nearestAssets(limit: Int) -> [DigitalAsset] {
        guard let origin = worldOriginLocation ?? userLocation else {
            return Array(nearbyAssets.prefix(limit))
        }
        return nearbyAssets
            .sorted { horizontalDistance(of: $0, from: origin) < horizontalDistance(of: $1, from: origin) }
            .prefix(limit)
            .map { $0 }
    }

    private func horizontalDistance(of asset: DigitalAsset, from origin: CLLocation) -> Double {
        guard let lat = asset.latitude, let lon = asset.longitude else { return .greatestFiniteMagnitude }
        return origin.distance(from: CLLocation(latitude: lat, longitude: lon))
    }


    // MARK: Place a single model — GeoTracking
    /// - Description: Anchors the model at its real-world coordinate using an
    /// ARGeoAnchor at the altitude it was posted at (with a sanity clamp).
    func placeAssetGeo(
        _ asset: DigitalAsset,
        in arView: ARView,
        cameraTransform: simd_float4x4?
    ) {
        if placedIds.contains(asset.id) { return }

        guard let lat = asset.latitude, let lon = asset.longitude else { return }

        let altitude = resolvedAltitude(for: asset, baseline: userLocation?.altitude ?? 0)
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        #if targetEnvironment(simulator)
        return
        #else
        placedIds.insert(asset.id)

        let geoAnchor = ARGeoAnchor(name: asset.name ?? "", coordinate: coord, altitude: altitude)
        arView.session.add(anchor: geoAnchor)
        let anchorEntity = AnchorEntity(anchor: geoAnchor)
        let generation = placementGeneration

        loadModel(for: asset) { [weak self] entity in
            guard let self, let arView = self.arView,
                  generation == self.placementGeneration else { return }
            anchorEntity.addChild(entity)
            arView.scene.addAnchor(anchorEntity)
            self.finishPlacement(of: asset, entity: entity)
        }
        #endif
    }


    // MARK: Place a single model — GPS / World tracking
    /// - Description: Computes the asset's east/north offset from the world
    /// origin location and drops it at that point in the gravity+heading
    /// aligned world (so -Z is north, +X is east).
    func placeAssetWorld(_ asset: DigitalAsset, in arView: ARView) {
        if placedIds.contains(asset.id) { return }
        guard let transform = worldTransform(for: asset) else { return }

        #if targetEnvironment(simulator)
        return
        #else
        placedIds.insert(asset.id)
        let anchorEntity = AnchorEntity(world: transform)
        let generation = placementGeneration

        loadModel(for: asset) { [weak self] entity in
            guard let self, let arView = self.arView,
                  generation == self.placementGeneration else { return }
            anchorEntity.addChild(entity)
            arView.scene.addAnchor(anchorEntity)
            self.worldAnchors[asset.id] = (anchorEntity, asset)
            self.finishPlacement(of: asset, entity: entity)
        }
        #endif
    }

    /// - Description: World-space transform for an asset in GPS mode: its
    /// east/north/up offset from `worldOriginLocation`, shifted by the camera
    /// position that location was captured at. Nil if out of trusted range.
    private func worldTransform(for asset: DigitalAsset) -> simd_float4x4? {
        guard
            let lat = asset.latitude,
            let lon = asset.longitude,
            let origin = worldOriginLocation
        else { return nil }

        let assetCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let assetGround = CLLocation(latitude: lat, longitude: lon)
        let originGround = CLLocation(latitude: origin.coordinate.latitude,
                                      longitude: origin.coordinate.longitude)

        let distance = originGround.distance(from: assetGround) // horizontal meters
        guard distance <= maxWorldPlacementMeters else {
            LocoloLog.debug(LocoloLog.ar, "skip asset out of range")
            return nil
        }

        let bearing = bearing(from: origin.coordinate, to: assetCoord) // radians CW from north
        let altitude = resolvedAltitude(for: asset, baseline: origin.altitude)

        // gravity+heading world: +X = east, +Y = up, -Z = north.
        let x = Float(distance * sin(bearing))
        let z = Float(-distance * cos(bearing))
        let y = Float(altitude - origin.altitude)

        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(x + worldOriginCameraOffset.x,
                                           y + worldOriginCameraOffset.y,
                                           z + worldOriginCameraOffset.z, 1)
        return transform
    }

    // MARK: GPS-mode re-anchoring
    /// - Description: World tracking drifts and the session-start GPS fix
    /// carries its own error, so after a long walk everything sits metres off.
    /// With a good fix, re-base the origin on the camera's current position
    /// and move already-placed anchors; ones now out of range are dropped.
    private func reanchorWorldOrigin() {
        guard trackingMode == .world, isLocalized,
              let loc = userLocation,
              loc.horizontalAccuracy > 0, loc.horizontalAccuracy <= reanchorMaxAccuracyMeters,
              let cam = arView?.session.currentFrame?.camera.transform
        else { return }

        worldOriginLocation = loc
        worldOriginCameraOffset = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)

        for (id, placed) in worldAnchors {
            if let transform = worldTransform(for: placed.asset) {
                placed.anchor.anchoring = AnchoringComponent(.world(transform: transform))
                placed.anchor.setTransformMatrix(transform, relativeTo: nil)
            } else {
                placed.anchor.removeFromParent()
                worldAnchors[id] = nil
                placedIds.remove(id)
            }
        }
    }


    // MARK: Shared model loading
    /// - Description: Downloads the USDZ, loads it, applies the poster's scale
    /// and rotation, then hands the ready entity to the mode-specific attach
    /// closure. Placement bookkeeping is shared via finishPlacement.
    private func loadModel(for asset: DigitalAsset, attach: @escaping (Entity) -> Void) {
        guard let url = URL(string: asset.fileUrl) else {
            placedIds.remove(asset.id)
            return
        }

        Task {
            do {
                // Reuse the on-disk cache and coalesce concurrent downloads,
                // so re-entering the viewer near the same assets is instant and
                // duplicate assets don't fetch the same bytes twice. (WS8)
                let localURL = try await self.localModelURL(for: url)

                let request = Entity.loadAsync(contentsOf: localURL)
                request
                    .sink(receiveCompletion: { completion in
                        if case let .failure(error) = completion {
                            LocoloLog.ar.error("model load error: \(error.localizedDescription, privacy: .public)")
                        }
                    }, receiveValue: { [weak self] entity in
                        guard let self else { return }
                        self.applyStoredTransform(to: entity, from: asset)
                        attach(entity)
                    })
                    .store(in: &self.modelLoadTokens)   // survives a geo→world switch (WS3.7)

            } catch {
                LocoloLog.ar.error("model download/load: \(error.localizedDescription, privacy: .public)")
                self.placedIds.remove(asset.id)
            }
        }
    }


    /// - Description: Resolves a local file URL for a USDZ, serving it from
    /// `MediaCache` when present, otherwise downloading once and caching it.
    /// Concurrent requests for the same remote URL share a single download so
    /// we never fetch the same asset twice at once. (WS8)
    private func localModelURL(for remoteURL: URL) async throws -> URL {
        if let cached = MediaCache.shared.localURL(forRemoteURL: remoteURL) {
            return cached
        }

        if let existing = inFlightDownloads[remoteURL] {
            return try await existing.value
        }

        let task = Task<URL, Error> {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let stored = MediaCache.shared.store(data: data, for: remoteURL, fileExtension: "usdz") else {
                throw URLError(.cannotCreateFile)
            }
            return stored
        }

        inFlightDownloads[remoteURL] = task
        defer { inFlightDownloads[remoteURL] = nil }
        return try await task.value
    }


    /// - Description: Applies the scale + rotation captured when the asset was placed.
    private func applyStoredTransform(to entity: Entity, from asset: DigitalAsset) {
        let sx = Float(asset.scaleX ?? 1)
        let sy = Float(asset.scaleY ?? 1)
        let sz = Float(asset.scaleZ ?? 1)
        entity.scale = [sx, sy, sz]

        // Prefer the world-space quaternion captured in the north-aligned
        // (.gravityAndHeading) frame — both placement modes anchor on a
        // north-aligned frame (ARGeoAnchor ENU / gravityAndHeading world), so
        // this reproduces the real-world facing direction across devices. Fall
        // back to legacy Euler angles for assets placed before WS2. (WS2)
        if let qx = asset.rotQX, let qy = asset.rotQY, let qz = asset.rotQZ, let qw = asset.rotQW {
            entity.orientation = simd_quatf(ix: Float(qx), iy: Float(qy), iz: Float(qz), r: Float(qw))
        } else {
            // Only pre-WS2 rows reach this branch, and those stored RADIANS
            // (prod rows hold ±π). Post-WS2 rows write degrees but always carry
            // a quaternion; the magnitude check covers any degree-valued stragglers.
            let raw = [asset.rotationX ?? 0, asset.rotationY ?? 0, asset.rotationZ ?? 0]
            let toRadians: Double = raw.allSatisfy { abs($0) <= 2 * .pi + 0.01 } ? 1 : .pi / 180
            let rx = Float(raw[0] * toRadians)
            let ry = Float(raw[1] * toRadians)
            let rz = Float(raw[2] * toRadians)

            let rotX = simd_quatf(angle: rx, axis: [1, 0, 0])
            let rotY = simd_quatf(angle: ry, axis: [0, 1, 0])
            let rotZ = simd_quatf(angle: rz, axis: [0, 0, 1])
            entity.transform.rotation = rotZ * rotY * rotX
        }
    }


    /// - Description: Post-attach bookkeeping shared by both modes: collision
    /// shapes for tap hit-testing, trigger registration, "explored" tracking,
    /// and a status update.
    private func finishPlacement(of asset: DigitalAsset, entity: Entity) {
        entity.generateCollisionShapes(recursive: true)
        triggerEngine.register(asset: asset, rootEntity: entity)
        revealIntoView(entity)          // materialize-in flourish
        startIdleBob(entity)            // gentle ambient life

        // Mark someone else's asset as explored for the AR profile.
        if let idString = SupabaseManager.shared.currentUserId,
           let viewerId = UUID(uuidString: idString),
           viewerId != asset.userId {
            Task {
                await SeenAssetsRepository.shared.recordSeen(userId: viewerId, assetId: asset.id)
            }
        }

        ARHaptics.discovery()
        statusMessage = "Placed \(asset.name ?? "asset")"
    }

    /// Scale the asset up from near-zero into its resting size, so it feels like
    /// it materializes into the world rather than popping in.
    private func revealIntoView(_ entity: Entity) {
        let resting = entity.transform
        var start = resting
        start.scale = resting.scale * 0.02
        entity.transform = start
        entity.move(to: resting, relativeTo: entity.parent,
                    duration: 0.55, timingFunction: .easeOut)
    }

    /// A slow vertical ping-pong so placed assets breathe instead of sitting
    /// frozen. Stops automatically once the entity leaves the scene. Trigger
    /// pops briefly override it and it resumes on the next tick.
    private func startIdleBob(_ entity: Entity) {
        // Kick off after the reveal settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak entity] in
            self?.bobStep(entity, up: true)
        }
    }

    private func bobStep(_ entity: Entity?, up: Bool) {
        guard let entity, entity.parent != nil else { return }
        var target = entity.transform
        target.translation.y += up ? 0.015 : -0.015
        entity.move(to: target, relativeTo: entity.parent,
                    duration: 2.2, timingFunction: .easeInOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) { [weak self] in
            self?.bobStep(entity, up: !up)
        }
    }


    // MARK: Geo helpers

    /// - Description: The altitude to anchor at. Uses the poster's stored
    /// altitude when it's within 30 m of the viewer's baseline (otherwise it's
    /// treated as a bad GPS fix and we anchor at the baseline).
    private func resolvedAltitude(for asset: DigitalAsset, baseline: Double) -> Double {
        if let stored = asset.altitudeM, abs(stored - baseline) <= 30 {
            return stored
        }
        return baseline
    }

    /// - Description: Initial bearing from one coordinate to another, in
    /// radians measured clockwise from true north.
    func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x)
    }


    // MARK: Manual test helper
    /// - Description: Places a test geo anchor at a coordinate.
    func placeGeoAnchorIfSupported(_ coordinate: CLLocationCoordinate2D) async {
        #if targetEnvironment(simulator)
        LocoloLog.debug(LocoloLog.ar, "simulator skip")
        return
        #else
        do {
            let anchor = try await ARGeoAnchor(coordinate: coordinate)
            let entity = AnchorEntity(anchor: anchor)
            arView?.scene.addAnchor(entity)
        } catch {
            LocoloLog.ar.error("geo anchor error: \(error.localizedDescription, privacy: .public)")
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
//  ARWorldTrackingConfiguration.worldAlignment (.gravityAndHeading)
//  https://developer.apple.com/documentation/arkit/arconfiguration/worldalignment
//
//  Location-based AR placement technique (bearing + distance → local ENU):
//  based on the approach used by ARKit+CoreLocation (ARCL).
//
//  RealityKit async model loading
//  https://developer.apple.com/documentation/realitykit/entity/loadasync
