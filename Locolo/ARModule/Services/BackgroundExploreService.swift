//
//  BackgroundExploreService.swift
//  Locolo
//
//  "Background AR" mode. iOS suspends the camera and ARKit the moment the app
//  leaves the screen — no app can keep an AR session rendering in the
//  background. What CAN persist is the part that matters on a walk:
//  location + audio. With this on, Locolo keeps a precise location session and
//  an audio session alive, and when you pass an asset that has a sound
//  (the creator's alert sound, or the asset's own audio sidecar) it plays it
//  — screen locked, phone in pocket — plus a notification you can tap to
//  jump straight back into AR.
//
//  Needs: `audio` + `location` in UIBackgroundModes (Info.plist), Always
//  location for best results (When-In-Use works while the session is live
//  because the blue pill keeps it in the foreground-equivalent state).
//

import Foundation
import Combine
import CoreLocation
import AVFoundation
import UserNotifications
import MediaPlayer
import Supabase

@MainActor
final class BackgroundExploreService: ObservableObject {
    static let shared = BackgroundExploreService()

    @Published private(set) var isOn = false
    @Published private(set) var lastPlayed: String?
    @Published private(set) var soundAssetsNearby = 0

    @Published var prefersOn: Bool {
        didSet { UserDefaults.standard.set(prefersOn, forKey: Self.prefKey) }
    }

    private static let prefKey = "ar.backgroundMode"
    private static let fetchRadius = 1500.0
    private static let refetchAfterMeters = 400.0
    private static let replayCooldown: TimeInterval = 30 * 60

    private struct SoundSpot {
        let id: UUID
        let name: String
        let coordinate: CLLocation
        let radius: Double
        let audioURL: URL
    }

    private var spots: [SoundSpot] = []
    private var lastFetch: CLLocation?
    private var lastPlayedAt: [UUID: Date] = [:]
    private var inside: Set<UUID> = []
    private var locationSub: AnyCancellable?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private let client = SupabaseManager.shared.client

    private init() {
        prefersOn = UserDefaults.standard.bool(forKey: Self.prefKey)
    }

    // MARK: - Lifecycle

    func toggle() {
        isOn ? stop() : start()
        prefersOn = isOn
    }

    func start() {
        guard !isOn else { return }
        isOn = true
        configureAudioSession()
        LocationManager.shared.setBackgroundExploring(true)
        LocationManager.shared.startTracking()
        locationSub = LocationManager.shared.$userLocation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] coord in
                Task { await self?.handle(CLLocation(latitude: coord.latitude, longitude: coord.longitude)) }
            }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        locationSub = nil
        player?.pause()
        player = nil
        spots = []
        inside = []
        lastFetch = nil
        LocationManager.shared.setBackgroundExploring(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Re-arm after sign-in if the user left it on.
    func restoreIfNeeded() {
        if prefersOn { start() }
    }

    // MARK: - Core loop

    private func handle(_ here: CLLocation) async {
        if lastFetch == nil || here.distance(from: lastFetch!) > Self.refetchAfterMeters {
            await fetchSpots(around: here)
        }
        for spot in spots {
            let d = here.distance(from: spot.coordinate)
            if d <= spot.radius {
                guard !inside.contains(spot.id) else { continue }
                inside.insert(spot.id)
                if let last = lastPlayedAt[spot.id], Date().timeIntervalSince(last) < Self.replayCooldown { continue }
                lastPlayedAt[spot.id] = Date()
                play(spot, distance: d)
            } else if d > spot.radius * 1.5 {
                inside.remove(spot.id)   // hysteresis: re-arm only after leaving
            }
        }
    }

    private func fetchSpots(around here: CLLocation) async {
        guard let assets: [DigitalAsset] = try? await client
            .rpc("get_nearby_assets_full", params: [
                "p_lat": here.coordinate.latitude,
                "p_lon": here.coordinate.longitude,
                "p_radius_meters": Self.fetchRadius
            ])
            .execute()
            .value else { return }
        lastFetch = here
        let visible = SafetyService.shared.visible(assets)

        // Creator-set alert sounds (V3 migration); absent before it's applied.
        struct AlertRow: Decodable { let asset_id: UUID; let alert_audio_url: String?; let alert_radius_m: Double? }
        let alerts: [AlertRow] = (try? await client
            .rpc("get_asset_alerts", params: ["p_assets": visible.map { $0.id.uuidString.lowercased() }])
            .execute()
            .value) ?? []
        let alertById = Dictionary(uniqueKeysWithValues: alerts.map { ($0.asset_id, $0) })

        spots = visible.compactMap { asset in
            guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
            let alert = alertById[asset.id]
            // Fall back to the asset's own audio sidecar (audio assets, songs).
            let urlString = alert?.alert_audio_url
                ?? (asset.mediaType == "audio" ? asset.mediaUrl : nil)
                ?? (asset.normalizedCategory == "audio" ? asset.fileUrl : nil)
            guard let urlString, let url = URL(string: urlString) else { return nil }
            return SoundSpot(id: asset.id, name: asset.name ?? "an AR asset",
                             coordinate: CLLocation(latitude: lat, longitude: lon),
                             radius: alert?.alert_radius_m ?? 60, audioURL: url)
        }
        soundAssetsNearby = spots.count
    }

    // MARK: - Playback

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps sound going with the screen locked; duckOthers
        // lowers the user's music instead of stopping it.
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func play(_ spot: SoundSpot, distance: Double) {
        configureAudioSession()
        let item = AVPlayerItem(url: MediaCache.shared.localURL(forRemoteURL: spot.audioURL) ?? spot.audioURL)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: item, queue: .main) { _ in
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        player = AVPlayer(playerItem: item)
        player?.play()
        lastPlayed = spot.name
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: spot.name,
            MPMediaItemPropertyArtist: "Locolo · AR nearby"
        ]

        let content = UNMutableNotificationContent()
        content.title = "🔊 You're passing “\(spot.name)”"
        content.body = "\(Int(distance)) m away. Open Locolo to see it in AR."
        content.userInfo = ["url": DeepLinkRouter.assetURL(for: spot.id).absoluteString]
        content.threadIdentifier = "background-ar"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "bgar-\(spot.id)", content: content, trigger: nil))
    }
}
