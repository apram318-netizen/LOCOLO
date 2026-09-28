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

    private struct SigningKeyRow: Decodable {
        let user_id: UUID
        let ed25519_public_key: String?
    }

    private struct SigningKeyUpsert: Encodable {
        let ed25519_public_key: String
        let signing_key_updated_at: String
    }

    private var signingCache: [UUID: String] = [:]

    /// Publish (or refresh) this user's chat + signing public keys. Idempotent.
    func publishMyKey(userId: UUID) async {
        guard let mine = CryptoService.shared.myPublicKeyBase64 else {
            print("KeyDirectory.publishMyKey skipped: Keychain unavailable")
            return
        }
        if await publicKey(for: userId) != mine {
            do {
                try await client
                    .from("users")
                    .update(KeyUpsert(
                        x25519_public_key: mine,
                        key_updated_at: ISO8601DateFormatter().string(from: Date())
                    ), returning: .minimal)
                    .eq("user_id", value: userId)
                    .execute()
                cache[userId] = mine
            } catch {
                print("KeyDirectory.publishMyKey failed:", error.localizedDescription)
            }
        }
        await publishSigningKey(userId: userId)
    }

    /// Publish the Ed25519 signing key used for asset-authenticity signatures.
    func publishSigningKey(userId: UUID) async {
        guard let mine = CryptoService.shared.mySigningPublicKeyBase64 else { return }
        if await signingKey(for: userId) == mine { return }
        do {
            try await client
                .from("users")
                .update(SigningKeyUpsert(
                    ed25519_public_key: mine,
                    signing_key_updated_at: ISO8601DateFormatter().string(from: Date())
                ), returning: .minimal)
                .eq("user_id", value: userId)
                .execute()
            signingCache[userId] = mine
        } catch {
            print("KeyDirectory.publishSigningKey failed:", error.localizedDescription)
        }
    }

    /// Fetch (and cache) a user's Ed25519 signing public key, for verifying
    /// their asset mint signatures.
    func signingKey(for userId: UUID) async -> String? {
        if let cached = signingCache[userId] { return cached }
        do {
            let rows: [SigningKeyRow] = try await client
                .from("users")
                .select("user_id, ed25519_public_key")
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
            let key = rows.first?.ed25519_public_key
            if let key { signingCache[userId] = key }
            return key
        } catch {
            return nil
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
