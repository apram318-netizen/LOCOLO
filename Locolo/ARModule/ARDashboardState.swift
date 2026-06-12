//
//  ARDashboardState.swift
//  Locolo
//
//  Module-wide state for the AR dashboard. Everything AR-specific that
//  used to live on app-level view models belongs here so the AR module
//  can evolve independently of the rest of the app.
//

import SwiftUI

enum ARRoute: Hashable {
    case viewer
    case create
    case profile
}

@MainActor
final class ARDashboardState: ObservableObject {
    @Published var path: [ARRoute] = []
    @Published var activeSection = "gallery"
}
