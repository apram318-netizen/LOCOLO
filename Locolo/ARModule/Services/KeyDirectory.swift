//
//  KeyDirectory.swift
//  Locolo
//
//  Publishes this device's chat public key and fetches peers' public keys from
//  Supabase (users.x25519_public_key, added in WS1.4) so conversation keys can
//  be derived. (WS6)
//

import Foundation
import Supabase

final class KeyDirectory {
    static let shared = KeyDirectory()

    private let client = SupabaseManager.shared.client
    private var cache: [UUID: String] = [:]

    private init() {}

    private struct KeyRow: Decodable {
        let user_id: UUID
        let x25519_public_key: String?
    }

    private struct KeyUpsert: Encodable {
        let x25519_public_key: String
        let key_updated_at: String
    }

    /// Publish (or refresh) this user's public key. Idempotent — safe to call
    /// on every launch; only writes if the stored key differs.
    func publishMyKey(userId: UUID) async {
        guard let mine = CryptoService.shared.myPublicKeyBase64 else {
            print("KeyDirectory.publishMyKey skipped: Keychain unavailable")
            return
        }
        if let existing = await publicKey(for: userId), existing == mine { return }

        do {
            try await client
                .from("users")
                .update(KeyUpsert(
                    x25519_public_key: mine,
                    key_updated_at: ISO8601DateFormatter().string(from: Date())
                ), returning: .minimal)   // users.email isn't selectable
                .eq("user_id", value: userId)
                .execute()
            cache[userId] = mine
        } catch {
            print("KeyDirectory.publishMyKey failed:", error.localizedDescription)
        }
    }

    /// Fetch (and cache) a peer's public key, or nil if they haven't published one.
    func publicKey(for userId: UUID) async -> String? {
        if let cached = cache[userId] { return cached }
        do {
            let rows: [KeyRow] = try await client
                .from("users")
                .select("user_id, x25519_public_key")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            let key = rows.first?.x25519_public_key
            if let key { cache[userId] = key }
            return key
        } catch {
            print("KeyDirectory.publicKey failed:", error.localizedDescription)
            return nil
        }
    }
}
