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

    enum CryptoError: Error { case badPeerKey, sealFailed, keychainUnavailable(OSStatus) }

    private enum KeychainRead {
        case found(Data)
        case missing
        case failed(OSStatus)
    }

    private let keychainAccount = "com.locolo.chat.x25519.identity"
    private let signingAccount = "com.locolo.provenance.ed25519.identity"
    private let hkdfInfo = Data("locolo-chat-v1".utf8)

    private var cachedPrivateKey: Curve25519.KeyAgreement.PrivateKey?
    private var cachedSigningKey: Curve25519.Signing.PrivateKey?
    private var conversationKeys: [String: SymmetricKey] = [:]

    private init() {}

    // MARK: - Identity key

    /// The device identity private key, created on first use and persisted in
    /// the Keychain (this-device-only, after-first-unlock).
    ///
    /// A new key is only minted when the item is genuinely absent. Any other
    /// Keychain failure (locked before first unlock, transient errors) throws:
    /// regenerating would orphan every existing conversation and republish a
    /// different public key.
    private func privateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let cached = cachedPrivateKey { return cached }

        switch loadKeychain(account: keychainAccount) {
        case .found(let data):
            if let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
                cachedPrivateKey = key
                return key
            }
        case .missing:
            break
        case .failed(let status):
            throw CryptoError.keychainUnavailable(status)
        }

        let key = Curve25519.KeyAgreement.PrivateKey()
        let status = saveKeychain(key.rawRepresentation, account: keychainAccount)
        guard status == errSecSuccess else { throw CryptoError.keychainUnavailable(status) }
        cachedPrivateKey = key
        return key
    }

    // MARK: - Signing identity (Ed25519) — authenticity / provenance

    /// The device's Ed25519 signing key, minted on first use. Separate from the
    /// key-agreement key above (agreement keys can't sign). Same mint-only-when-
    /// absent safety so a locked Keychain never silently rotates it.
    private func signingKey() throws -> Curve25519.Signing.PrivateKey {
        if let cached = cachedSigningKey { return cached }
        switch loadKeychain(account: signingAccount) {
        case .found(let data):
            if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
                cachedSigningKey = key
                return key
            }
        case .missing:
            break
        case .failed(let status):
            throw CryptoError.keychainUnavailable(status)
        }
        let key = Curve25519.Signing.PrivateKey()
        let status = saveKeychain(key.rawRepresentation, account: signingAccount)
        guard status == errSecSuccess else { throw CryptoError.keychainUnavailable(status) }
        cachedSigningKey = key
        return key
    }

    /// Base64 Ed25519 public key to publish so others can verify this device's
    /// signatures, or nil if the Keychain can't be read.
    var mySigningPublicKeyBase64: String? {
        try? signingKey().publicKey.rawRepresentation.base64EncodedString()
    }

    /// Sign a message string, returning a base64 signature (or nil on failure).
    func sign(_ message: String) -> String? {
        guard let key = try? signingKey(),
              let sig = try? key.signature(for: Data(message.utf8)) else { return nil }
        return sig.base64EncodedString()
    }

    /// Verify a base64 Ed25519 signature over `message` against a base64 public key.
    static func verify(signatureBase64: String, message: String, publicKeyBase64: String) -> Bool {
        guard let sig = Data(base64Encoded: signatureBase64),
              let pubData = Data(base64Encoded: publicKeyBase64),
              let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else { return false }
        return pub.isValidSignature(sig, for: Data(message.utf8))
    }

    /// SHA-256 hex of arbitrary data — the content hash for asset authenticity.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// SHA-256 hex of a string (used to recompute provenance record hashes).
    static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    /// Base64 raw public key to publish so others can encrypt to this device,
    /// or nil if the Keychain can't be read right now.
    var myPublicKeyBase64: String? {
        try? privateKey().publicKey.rawRepresentation.base64EncodedString()
    }

    /// Human-comparable fingerprint of a public key ("12345 67890 …"), so two
    /// people can check in person that nobody swapped keys in the directory.
    static func safetyCode(forPublicKeyBase64 base64: String) -> String {
        guard let raw = Data(base64Encoded: base64) else { return "—" }
        let digest = Array(SHA256.hash(data: raw))
        return stride(from: 0, to: 20, by: 5).map { start -> String in
            let chunk = digest[start..<start + 5].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            return String(format: "%05llu", chunk % 100_000)
        }.joined(separator: " ")
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

    @discardableResult
    private func saveKeychain(_ data: Data, account: String) -> OSStatus {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attrs as CFDictionary, nil)
    }

    private func loadKeychain(account: String) -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            guard let data = out as? Data else { return .failed(status) }
            return .found(data)
        case errSecItemNotFound:
            return .missing
        default:
            return .failed(status)
        }
    }
}
