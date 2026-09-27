//
//  ProximityNotifier.swift
//  Locolo
//
//  "You're 43 m from “Neon Koi” by @maya" — a local notification when the
//  user walks within 100 m of someone's AR creation.
//
//  How it stays cheap and quiet:
//    • Rides the app's existing location stream (LocationManager.$userLocation,
//      ≤100 m accuracy fixes only) — no extra GPS sessions.
//    • Fetches candidates within 1 km, and only again after moving 300 m or
//      after 10 minutes.
//    • Hysteresis: an asset alerts when you come within 100 m and re-arms only
//      after you've been more than 150 m away; each asset then waits 6 h.
//    • At most one alert every 3 minutes and 12 a day; the nearest creation
//      wins and the rest are summarised ("+2 more within 100 m").
//    • Never for your own work, blocked creators, reported assets, or while
//      the AR viewer is open (you're already looking).
//    • Also geofences the 15 nearest candidates, so iOS wakes the app for an
//      alert even after it has been terminated.
//

import Foundation
import CoreLocation
import Combine
import UIKit
import Supabase

@MainActor
final class ProximityNotifier: NSObject {
    static let shared = ProximityNotifier()

    static let alertRadius: CLLocationDistance = 100
    static let rearmRadius: CLLocationDistance = 150
    static let fetchRadius: Double = 1_000
    static let refetchDistance: CLLocationDistance = 300
    static let refetchInterval: TimeInterval = 600
    static let perAssetCooldown: TimeInterval = 6 * 3600
    static let globalCooldown: TimeInterval = 180
    static let dailyCap = 12
    static let maxRegions = 15
    private static let regionPrefix = "ar-nearby-"

    /// Set by the AR viewer while it's on screen.
    var isViewerActive = false

    struct Candidate: Codable, Hashable {
        let id: UUID
        let name: String
        let creatorId: UUID
        let latitude: Double
        let longitude: Double
        let locationName: String?
        let category: String?
        let thumbUrl: String?

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    private let client = SupabaseManager.shared.client
    private let regionManager = CLLocationManager()
    private var cancellable: AnyCancellable?
    private var me: UUID?
    private var candidates: [Candidate] = []
    private var inRange: Set<UUID> = []
    private var lastAlertByAsset: [String: Double] = [:]
    private var alertLog: [Double] = []
    private var lastFetchLocation: CLLocation?
    private var lastFetchAt: Date?
    private var isFetching = false
    private var awaitingRegionFix = false

    private enum Keys {
        static let candidates = "ar.nearby.candidates"
        static let inRange = "ar.nearby.inRange"
        static let lastAlert = "ar.nearby.lastAlert"
        static let log = "ar.nearby.log"
    }

    private override init() {
        super.init()
        regionManager.delegate = self
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.candidates),
           let saved = try? JSONDecoder().decode([Candidate].self, from: data) {
            candidates = saved
        }
        inRange = Set((defaults.stringArray(forKey: Keys.inRange) ?? []).compactMap(UUID.init(uuidString:)))
        lastAlertByAsset = defaults.dictionary(forKey: Keys.lastAlert) as? [String: Double] ?? [:]
        alertLog = defaults.array(forKey: Keys.log) as? [Double] ?? []
    }

    // MARK: Session

    func start(me: UUID) {
        self.me = me
        guard cancellable == nil else { return }
        cancellable = LocationManager.shared.$userLocation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .throttle(for: .seconds(4), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] coordinate in
                Task { await self?.handle(CLLocation(latitude: coordinate.latitude,
                                                     longitude: coordinate.longitude)) }
            }
    }

    func stop() {
        cancellable = nil
        me = nil
        candidates = []
        inRange = []
        lastFetchLocation = nil
        lastFetchAt = nil
        for region in regionManager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            regionManager.stopMonitoring(for: region)
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.candidates)
        defaults.removeObject(forKey: Keys.inRange)
    }

    // MARK: Location ticks

    private func handle(_ here: CLLocation) async {
        guard NotificationPreferences.shared.prefs.nearby else { return }
        if needsFetch(at: here) { await fetchCandidates(around: here) }
        await evaluate(at: here)
    }

    private func needsFetch(at here: CLLocation) -> Bool {
        guard me != nil, !isFetching else { return false }
        guard let lastFetchLocation, let lastFetchAt else { return true }
        return here.distance(from: lastFetchLocation) > Self.refetchDistance
            || Date().timeIntervalSince(lastFetchAt) > Self.refetchInterval
    }

    private func fetchCandidates(around here: CLLocation) async {
        guard let me else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let assets: [DigitalAsset] = try await client
                .rpc("get_nearby_assets_full", params: [
                    "p_lat": here.coordinate.latitude,
                    "p_lon": here.coordinate.longitude,
                    "p_radius_meters": Self.fetchRadius
                ])
                .execute()
                .value
            let visible = SafetyService.shared.visible(assets).filter { $0.userId != me }
            candidates = visible.compactMap { asset in
                guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
                return Candidate(id: asset.id,
                                 name: asset.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                                     ?? "Untitled creation",
                                 creatorId: asset.userId,
                                 latitude: lat, longitude: lon,
                                 locationName: asset.locationName?.nilIfEmpty,
                                 category: asset.category?.nilIfEmpty,
                                 thumbUrl: asset.thumbUrl)
            }
            lastFetchLocation = here
            lastFetchAt = Date()
            await CreatorCache.shared.load(candidates.map(\.creatorId))
            persistCandidates()
            updateGeofences(around: here)
        } catch {
            print("Nearby art fetch failed:", error.localizedDescription)
        }
    }

    // MARK: Decide

    private func evaluate(at here: CLLocation) async {
        let blocked = SafetyService.shared.blockedUserIds
        let hidden = SafetyService.shared.hiddenAssetIds
        let measured = candidates
            .filter { !blocked.contains($0.creatorId) && !hidden.contains($0.id) }
            .map { (candidate: $0, distance: here.distance(from: $0.location)) }
        let distanceById = Dictionary(measured.map { ($0.candidate.id, $0.distance) },
                                      uniquingKeysWith: { a, _ in a })

        // Re-arm anything we've clearly walked away from (or that's gone).
        inRange = inRange.filter { id in
            guard let d = distanceById[id] else { return false }
            return d <= Self.rearmRadius
        }

        let within = measured
            .filter { $0.distance <= Self.alertRadius }
            .sorted { $0.distance < $1.distance }
        let newlyInRange = within.filter { !inRange.contains($0.candidate.id) }
        inRange.formUnion(within.map(\.candidate.id))
        UserDefaults.standard.set(inRange.map(\.uuidString), forKey: Keys.inRange)

        guard !isViewerActive, !newlyInRange.isEmpty,
              NotificationPrefs.allowsNearby else { return }

        let now = Date().timeIntervalSince1970
        let eligible = newlyInRange.filter { entry in
            now - (lastAlertByAsset[entry.candidate.id.uuidString] ?? 0) > Self.perAssetCooldown
        }
        guard let pick = eligible.first else { return }

        alertLog = alertLog.filter { now - $0 < 86_400 }
        if let last = alertLog.max(), now - last < Self.globalCooldown { return }
        guard alertLog.count < Self.dailyCap else { return }

        lastAlertByAsset[pick.candidate.id.uuidString] = now
        lastAlertByAsset = lastAlertByAsset.filter { now - $0.value < Self.perAssetCooldown * 4 }
        alertLog.append(now)
        UserDefaults.standard.set(lastAlertByAsset, forKey: Keys.lastAlert)
        UserDefaults.standard.set(alertLog, forKey: Keys.log)

        await post(pick.candidate, distance: pick.distance, from: here, othersNearby: within.count - 1)
    }

    // MARK: Notify

    private func post(_ c: Candidate, distance: CLLocationDistance, from here: CLLocation, othersNearby: Int) async {
        let meters = max(1, Int(distance.rounded()))
        let direction = Self.compassDirection(from: here, to: c.location)
        let creator = CreatorCache.shared.creator(c.creatorId)
        let byLine = creator.map { "by @\($0.username)" }

        var sentences: [String] = []
        var lead = "\(meters) m \(direction) of you"
        if let place = c.locationName { lead += " near \(place)" }
        if let category = c.category { lead += " · \(category.capitalized)" }
        sentences.append(lead + ".")
        if DiscoveryStore.shared.hasFound(c.id) {
            sentences.append("You've found this one before — say hi again.")
        } else {
            sentences.append("Open the AR camera to discover it.")
        }
        if othersNearby > 0 {
            sentences.append("+\(othersNearby) more AR creation\(othersNearby == 1 ? "" : "s") within 100 m.")
        }

        await ARNotificationRouter.post(.init(
            id: "nearby-\(c.id.uuidString.lowercased())",
            title: "✨ “\(c.name)” is \(meters) m away",
            subtitle: byLine.map { "AR art \($0)" } ?? "AR art nearby",
            body: sentences.joined(separator: " "),
            url: DeepLinkRouter.assetURL(for: c.id),
            category: ARNotificationRouter.nearbyCategory,
            thread: "nearby",
            type: "nearby",
            extra: ["assetId": c.id.uuidString.lowercased(), "distance": String(meters)],
            imageURL: c.thumbUrl.flatMap(URL.init(string:)),
            relevance: max(0.3, 1 - distance / Self.alertRadius)))
    }

    static func compassDirection(from a: CLLocation, to b: CLLocation) -> String {
        let lat1 = a.coordinate.latitude * .pi / 180
        let lat2 = b.coordinate.latitude * .pi / 180
        let dLon = (b.coordinate.longitude - a.coordinate.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        return names[Int((bearing + 22.5) / 45) % 8]
    }

    // MARK: Geofences (wake the app when it isn't running)

    private func persistCandidates() {
        if let data = try? JSONEncoder().encode(candidates) {
            UserDefaults.standard.set(data, forKey: Keys.candidates)
        }
    }

    private func updateGeofences(around here: CLLocation) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              regionManager.authorizationStatus == .authorizedAlways else { return }
        for region in regionManager.monitoredRegions where region.identifier.hasPrefix(Self.regionPrefix) {
            regionManager.stopMonitoring(for: region)
        }
        let nearest = candidates
            .sorted { here.distance(from: $0.location) < here.distance(from: $1.location) }
            .prefix(Self.maxRegions)
        for c in nearest {
            let region = CLCircularRegion(center: c.location.coordinate, radius: Self.alertRadius,
                                          identifier: Self.regionPrefix + c.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            regionManager.startMonitoring(for: region)
        }
    }

    private func handleRegionEntry() {
        guard NotificationPrefs.allowsNearby else { return }
        if let fix = regionManager.location,
           Date().timeIntervalSince(fix.timestamp) < 30, fix.horizontalAccuracy <= 100 {
            Task { await evaluate(at: fix) }
        } else {
            awaitingRegionFix = true
            regionManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            regionManager.requestLocation()
        }
    }

    private func handleFix(_ fix: CLLocation) {
        guard awaitingRegionFix, fix.horizontalAccuracy <= 100 else { return }
        awaitingRegionFix = false
        Task { await evaluate(at: fix) }
    }
}

extension ProximityNotifier: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("ar-nearby-") else { return }
        Task { @MainActor in ProximityNotifier.shared.handleRegionEntry() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in ProximityNotifier.shared.handleFix(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in ProximityNotifier.shared.awaitingRegionFix = false }
    }
}

private extension NotificationPrefs {
    /// Read from the local mirror so it also works on a background relaunch.
    static var allowsNearby: Bool { NotificationPreferences.localSnapshot().nearby }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
