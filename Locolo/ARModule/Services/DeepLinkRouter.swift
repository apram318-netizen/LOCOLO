//
//  DeepLinkRouter.swift
//  Locolo
//
//  Holds an incoming `locolo://asset/<uuid>` or `locolo://user/<uuid>` link
//  until the signed-in UI is on screen. URLs are caught at the ContentView
//  level (always mounted), so a cold launch that lands on the splash or
//  sign-in screen doesn't drop the link — ARAppRootView consumes asset links
//  and ARDashboardRootView consumes profile links once authenticated.
//

import Foundation

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private init() {}

    @Published var pendingAssetId: UUID?
    @Published var pendingUserId: UUID?
    /// Screens reached from notifications: `locolo://chat/<id>`,
    /// `locolo://activity`, `locolo://messages`, `locolo://viewer`.
    @Published var pendingRoute: ARRoute?

    /// - Returns: whether the URL was a Locolo link we understood.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        if let assetId = Self.assetId(from: url) {
            pendingAssetId = assetId
            return true
        }
        if let userId = Self.userId(from: url) {
            pendingUserId = userId
            return true
        }
        if let route = Self.route(from: url) {
            pendingRoute = route
            return true
        }
        return false
    }

    func consume() -> UUID? {
        defer { pendingAssetId = nil }
        return pendingAssetId
    }

    func consumeUser() -> UUID? {
        defer { pendingUserId = nil }
        return pendingUserId
    }

    func consumeRoute() -> ARRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    static func chatURL(for conversationId: String) -> URL? {
        URL(string: "locolo://chat/\(conversationId)")
    }

    static func route(from url: URL) -> ARRoute? {
        guard url.scheme?.lowercased() == "locolo", let host = url.host?.lowercased() else { return nil }
        switch host {
        case "chat":
            guard let id = url.pathComponents.last, id != "/", !id.isEmpty else { return .conversations }
            return .chat(conversationId: id)
        case "messages", "inbox": return .conversations
        case "activity", "notifications": return .activity
        case "viewer", "ar": return .viewer
        default: return nil
        }
    }

    static func assetURL(for assetId: UUID) -> URL {
        URL(string: "locolo://asset/\(assetId.uuidString.lowercased())")!
    }

    static func userURL(for userId: UUID) -> URL {
        URL(string: "locolo://user/\(userId.uuidString.lowercased())")!
    }

    static func assetId(from url: URL) -> UUID? {
        id(from: url, hosts: ["asset"])
    }

    static func userId(from url: URL) -> UUID? {
        id(from: url, hosts: ["user", "profile"])
    }

    private static func id(from url: URL, hosts: Set<String>) -> UUID? {
        guard url.scheme?.lowercased() == "locolo",
              let host = url.host?.lowercased(), hosts.contains(host),
              let idString = url.pathComponents.last
        else { return nil }
        return UUID(uuidString: idString)
    }
}
