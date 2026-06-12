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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: return "Tap"
        case .proximity: return "Walk close"
        case .speech: return "Say a phrase"
        case .shake: return "Shake phone"
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

    enum CodingKeys: String, CodingKey {
        case distanceM = "distance_m"
        case phrase
        case shakePattern = "shake_pattern"
    }
}
