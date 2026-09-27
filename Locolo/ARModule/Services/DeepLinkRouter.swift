//
//  DeepLinkRouter.swift
//  Locolo
//
//  Holds an incoming `locolo://asset/<uuid>` link until the signed-in UI is
//  on screen. URLs are caught at the ContentView level (always mounted), so
//  a cold launch that lands on the splash or sign-in screen doesn't drop
//  the link — ARAppRootView consumes it once the user is authenticated.
//

import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private init() {}

    @Published var pendingAssetId: UUID?

    /// - Returns: whether the URL was a Locolo link we understood.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let assetId = Self.assetId(from: url) else { return false }
        pendingAssetId = assetId
        return true
    }

    func consume() -> UUID? {
        defer { pendingAssetId = nil }
        return pendingAssetId
    }

    static func assetURL(for assetId: UUID) -> URL {
        URL(string: "locolo://asset/\(assetId.uuidString.lowercased())")!
    }

    static func assetId(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "locolo", url.host?.lowercased() == "asset",
              let idString = url.pathComponents.last
        else { return nil }
        return UUID(uuidString: idString)
    }
}
