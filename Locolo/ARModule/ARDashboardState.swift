//
//  ARDashboardState.swift
//  Locolo
//
//  Module-wide state for the AR dashboard. Everything AR-specific that
//  used to live on app-level view models belongs here so the AR module
//  can evolve independently of the rest of the app.
//

import SwiftUI

// MARK: - Tabs

/// The four primary sections of the standalone AR experience.
enum ARTab: String, CaseIterable, Identifiable {
    case explore
    case nearby
    case search
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Explore"
        case .nearby: return "Nearby"
        case .search: return "Search"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .explore: return "sparkles.rectangle.stack"
        case .nearby: return "map"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle"
        }
    }

    var filledIcon: String {
        switch self {
        case .explore: return "sparkles.rectangle.stack.fill"
        case .nearby: return "map.fill"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

// MARK: - Pushed routes

/// Destinations pushed on top of the tabbed dashboard (they cover the tab bar).
enum ARRoute: Hashable {
    case viewer
    case create
    case collection
    case wishlist
    case profile(userId: UUID)                       // WS4 public creator profile
    case followList(userId: UUID, followers: Bool)   // WS4 followers / following list
    case conversations                               // WS6 E2E messages inbox
    case settings                                    // account, safety, sign out
    case chat(conversationId: String)                // WS6 single conversation
}

// MARK: - State

@MainActor
final class ARDashboardState: ObservableObject {
    @Published var selectedTab: ARTab = .explore
    @Published var path: [ARRoute] = []

    /// Switch tabs with the module's standard spring + a light haptic tick.
    func select(_ tab: ARTab) {
        guard tab != selectedTab else { return }
        ARHaptics.tick()
        withAnimation(ARDesign.spring) {
            selectedTab = tab
        }
    }
}
