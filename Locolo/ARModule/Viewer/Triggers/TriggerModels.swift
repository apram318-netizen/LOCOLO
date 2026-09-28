//
//  TriggerModels.swift
//  Locolo
//
//  One trigger per asset, chosen at post time. The type lives in
//  digital_assets.trigger_type and the parameters in trigger_config (jsonb).
//

import Foundation

enum TriggerType: String, Codable, CaseIterable, Identifiable {
    case tap
    case proximity
    case speech
    case shake
    case gaze
    case timeOfDay = "time_of_day"
    case longPress = "long_press"
    case multiTap = "multi_tap"
    case walkAround = "walk_around"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: return "Tap"
        case .proximity: return "Walk close"
        case .speech: return "Say a phrase"
        case .shake: return "Shake phone"
        case .gaze: return "Look at it"
        case .timeOfDay: return "Time of day"
        case .longPress: return "Long-press"
        case .multiTap: return "Multi-tap"
        case .walkAround: return "Walk around"
        }
    }
}

enum ShakePattern: String, Codable, CaseIterable, Identifiable {
    case single
    case double
    case tilt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "Single shake"
        case .double: return "Double shake"
        case .tilt: return "Tilt"
        }
    }
}

struct TriggerConfig: Codable {
    var distanceM: Double?
    var phrase: String?
    var shakePattern: ShakePattern?
    /// Gaze: how long (seconds) the camera must look at the asset.
    var gazeSeconds: Double?
    /// Time-of-day window in local hours (0–23). Inclusive start, exclusive end unless equal (always).
    var startHour: Int?
    var endHour: Int?
    /// Multi-tap: required tap count (default 3).
    var tapCount: Int?
    /// Walk-around: degrees of orbit around the asset before firing (default 270).
    var orbitDegrees: Double?

    enum CodingKeys: String, CodingKey {
        case distanceM = "distance_m"
        case phrase
        case shakePattern = "shake_pattern"
        case gazeSeconds = "gaze_seconds"
        case startHour = "start_hour"
        case endHour = "end_hour"
        case tapCount = "tap_count"
        case orbitDegrees = "orbit_degrees"
    }
}
