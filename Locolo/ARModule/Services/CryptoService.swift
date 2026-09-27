//
//  CryptoService.swift
//  Locolo
//
//  End-to-end encryption for chat (WS6). Each device holds a long-lived
//  Curve25519 key-agreement identity key in the Keychain. A per-conversation
//  AES-GCM key is derived from the X25519 shared secret via HKDF, so the server
//  only ever sees ciphertext.
//
//  Limitation (documented): static-key X25519 + AES-GCM gives confidentiality
//  and integrity but NO forward secrecy. A Double Ratchet is a future upgrade.
//

import Foundation
import CryptoKit
import Security

final class CryptoService {
    static let shared = CryptoService()

    enum CryptoError: Error { case badPeerKey, sealFailed }

    private let keychainAccount = "com.locolo.chat.x25519.identity"
    private let hkdfInfo = Data("locolo-chat-v1".utf8)

    private var cachedPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var conversationKeys: [String: SymmetricKey] = [:]

    private init() {}

    // MARK: - Identity key

    /// The device identity private key, created on first use and persisted in
    /// the Keychain (this-device-only, after-first-unlock).
    private func privateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let cached = cachedPrivateKey { return cached }

        if let data = loadKeychain(),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            cachedPrivateKey = key
            return key
        }

        let key = Curve25519.KeyAgreement.PrivateKey()
        saveKeychain(key.rawRepresentation)
        cachedPrivateKey = key
        return key
    }

    /// Base64 raw public key to publish so others can encrypt to this device.
    var myPublicKeyBase64: String {
        privateKey().publicKey.rawRepresentation.base64EncodedString()
    }

    // MARK: - Conversation key

    /// Derives (and caches) the symmetric key for a conversation from this
    /// device's private key and the peer's published public key. Both sides
    /// derive the same key because the X25519 shared secret is symmetric.
    func conversationKey(conversationId: String, peerPublicKeyBase64: String) throws -> SymmetricKey {
        if let cached = conversationKeys[conversationId] { return cached }

        guard let peerData = Data(base64Encoded: peerPublicKeyBase64) else {
            throw CryptoError.badPeerKey
        }
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData)
        let shared = try privateKey().sharedSecretFromKeyAgreement(with: peerKey)

        let symmetric = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(conversationId.utf8),
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )
        conversationKeys[conversationId] = symmetric
        return symmetric
    }

    // MARK: - Seal / open

    /// Encrypts plaintext → base64(nonce‖ciphertext‖tag).
    func seal(_ plaintext: String, key: SymmetricKey) throws -> String {
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealed.combined else { throw CryptoError.sealFailed }
        return combined.base64EncodedString()
    }

    /// Decrypts base64(nonce‖ciphertext‖tag) → plaintext, or nil if it isn't
    /// valid ciphertext for this key (e.g. legacy plaintext or wrong key).
    func open(_ ciphertextBase64: String, key: SymmetricKey) -> String? {
        guard
            let data = Data(base64Encoded: ciphertextBase64),
            let box = try? AES.GCM.SealedBox(combined: data),
            let plain = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - Keychain

    private func saveKeychain(_ data: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private func loadKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}
