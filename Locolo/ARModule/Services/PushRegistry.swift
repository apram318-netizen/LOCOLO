//
//  PushRegistry.swift
//  Locolo
//
//  Owns this device's APNs token: registers it for the signed-in account
//  (register_device_token reassigns a shared phone to whoever is signed in)
//  and removes it on sign-out. Also reads app_config.push_enabled — while the
//  server isn't sending pushes, the app posts local notifications for new
//  activity and messages itself; once it is, those fallbacks switch off so
//  nothing arrives twice.
//

import Foundation
import UIKit
import Supabase

@MainActor
final class PushRegistry {
    static let shared = PushRegistry()
    private init() {}

    private let client = SupabaseManager.shared.client
    private let tokenKey = "ar.push.deviceToken"
    private let serverKey = "ar.push.serverActive"
    private var me: UUID?
    private var registeredFor: (token: String, user: UUID)?

    /// True once the backend confirms it delivers remote pushes.
    private(set) var serverPushActive: Bool {
        get { UserDefaults.standard.bool(forKey: serverKey) }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }

    private var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    // MARK: Session

    func start(me: UUID) async {
        self.me = me
        UIApplication.shared.registerForRemoteNotifications()
        await refreshServerFlag()
        await registerIfPossible()
    }

    /// Call while still signed in (the RPC needs the session).
    func unregister() async {
        defer {
            me = nil
            registeredFor = nil
        }
        guard let token else { return }
        _ = try? await client
            .rpc("unregister_device_token", params: ["p_token": token])
            .execute()
    }

    // MARK: AppDelegate hooks

    nonisolated static func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            shared.token = hex
            await shared.registerIfPossible()
        }
    }

    nonisolated static func didFailToRegister(_ error: Error) {
        print("APNs registration failed:", error.localizedDescription)
    }

    // MARK: Internals

    private func registerIfPossible() async {
        guard let me, let token else { return }
        if let registeredFor, registeredFor.token == token, registeredFor.user == me { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await client
                .rpc("register_device_token", params: [
                    "p_token": token,
                    "p_environment": environment,
                    "p_bundle": Bundle.main.bundleIdentifier ?? ""
                ])
                .execute()
            registeredFor = (token, me)
        } catch {
            if !EngagementStore.isMissingSchema(error) {
                print("Device token registration failed:", error.localizedDescription)
            }
        }
    }

    private struct ConfigRow: Decodable {
        let value: Bool?
    }

    private func refreshServerFlag() async {
        do {
            let rows: [ConfigRow] = try await client
                .from("app_config")
                .select("value")
                .eq("key", value: "push_enabled")
                .limit(1)
                .execute()
                .value
            serverPushActive = rows.first?.value ?? false
        } catch {
            serverPushActive = false
        }
    }

    /// A remote push reached us, so the pipeline is live regardless of flags.
    func noteRemotePushReceived() {
        serverPushActive = true
    }
}
