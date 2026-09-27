//
//  ChatViewModel.swift
//  Locolo
//
//  Real-time chat with end-to-end encryption (WS6). Messages travel and rest as
//  ciphertext; this view model derives the conversation key (from the peer's
//  published public key), decrypts what comes in, and encrypts what goes out.
//

import Foundation
import CryptoKit

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [Message] = []       // decrypted for display
    /// True when the peer's published key differs from the one we last saw —
    /// a "safety number changed" signal (key rotation or a possible MITM). (WS6)
    @Published var peerKeyChanged = false
    /// Set when a message can't be sent securely (peer has no key yet).
    @Published var sendError: String?

    private let repo = ChatRepository()
    private var conversationId: String            // Firestore document ID for the chat
    private var userId: String
    private let peerId: UUID?                      // explicit peer, else derived from the conversation
    private var conversationKey: SymmetricKey?     // nil until the peer key resolves
    private var rawMessages: [Message] = []        // ciphertext as received
    private var listenerTask: Task<Void, Never>?

    // MARK: Init
    init(conversationId: String, userId: String, peerId: UUID? = nil) {
        self.conversationId = conversationId
        self.userId = userId
        self.peerId = peerId
        startListening()
        Task { await prepareKey() }
    }

    // MARK: - E2E key setup

    /// Resolves the peer (explicit or from the conversation participants),
    /// fetches their public key, and derives the shared conversation key.
    private func prepareKey() async {
        var peer = peerId
        if peer == nil {
            let parts = (try? await repo.fetchParticipants(conversationId: conversationId)) ?? []
            peer = parts
                .first { $0.lowercased() != userId.lowercased() }
                .flatMap { UUID(uuidString: $0) }
        }
        guard let peer, let peerKey = await KeyDirectory.shared.publicKey(for: peer) else { return }

        // Safety-number check: warn if the peer's key differs from the one we
        // last pinned for them (key rotation, new device, or a possible MITM).
        let pinKey = "peerKey_\(peer.uuidString.lowercased())"
        if let pinned = UserDefaults.standard.string(forKey: pinKey), pinned != peerKey {
            peerKeyChanged = true
        }
        UserDefaults.standard.set(peerKey, forKey: pinKey)

        conversationKey = try? CryptoService.shared.conversationKey(
            conversationId: conversationId,
            peerPublicKeyBase64: peerKey
        )
        applyDecryption()
    }

    /// Rebuilds `messages` from `rawMessages`, decrypting with the conversation
    /// key when available. Before the key resolves, legacy plaintext still
    /// reads but anything that looks like ciphertext shows a lock instead of
    /// base64 noise.
    private func applyDecryption() {
        messages = rawMessages.map { message in
            var copy = message
            if let key = conversationKey {
                copy.decryptedText = CryptoService.shared.open(message.text, key: key)
            } else {
                copy.decryptedText = Self.looksLikeCiphertext(message.text) ? nil : message.text
            }
            return copy
        }
    }

    /// AES-GCM combined output is ≥ 28 bytes (12 nonce + 16 tag), so its
    /// base64 is ≥ 40 chars with no spaces.
    private static func looksLikeCiphertext(_ text: String) -> Bool {
        text.count >= 40 && !text.contains(" ") && Data(base64Encoded: text) != nil
    }

    // MARK: FUNCTION: startListening
    private func startListening() {
        let stream = repo.listenMessages(conversationId: conversationId, forUser: userId)
        listenerTask = Task { [weak self] in
            for await newMessages in stream {
                guard let self else { return }
                await MainActor.run {
                    self.rawMessages = newMessages
                    self.applyDecryption()

                    // Notify on a new incoming message — with the DECRYPTED body,
                    // never the raw ciphertext. If we can't decrypt yet, show a
                    // generic line rather than base64 garbage.
                    if let last = newMessages.last, last.senderId != self.userId,
                       last.id != self.getLastNotifiedId() {
                        self.setLastNotifiedId(last.id)
                        var display = last
                        if let key = self.conversationKey {
                            display.text = CryptoService.shared.open(last.text, key: key) ?? "New message"
                        }
                        NotificationManager.shared
                            .showInAppNotification(for: display, conversationId: self.conversationId)
                    }
                }
            }
        }
    }

    // MARK: FUNCTION: sendMessage
    /// Encrypts the body and sends ciphertext with a privacy-preserving
    /// conversation preview. Never falls back to plaintext: if the peer has
    /// no published key the send is refused and `sendError` explains why.
    /// - Returns: whether the message was sent.
    @discardableResult
    func sendMessage(_ text: String, senderId: String, senderName: String) async -> Bool {
        sendError = nil
        if conversationKey == nil {
            // The key may still be resolving (or the peer just published one).
            await prepareKey()
        }
        guard let key = conversationKey, let sealed = try? CryptoService.shared.seal(text, key: key) else {
            sendError = "Can't send securely yet — this person hasn't set up encrypted chat. They'll be able to receive messages after they next open Locolo."
            return false
        }

        let msg = Message(
            senderId: senderId.lowercased(),
            senderName: senderName,
            text: sealed,
            time: Date()
        )
        do {
            try await repo.sendMessage(conversationId: conversationId, message: msg,
                                       lastMessagePreview: "🔒 Encrypted message")
            return true
        } catch {
            sendError = "Message didn't send. Check your connection and try again."
            return false
        }
    }

    deinit {
        listenerTask?.cancel()
    }

    private func getLastNotifiedId() -> String? {
        UserDefaults.standard.string(forKey: "lastNotified_\(conversationId)")
    }

    private func setLastNotifiedId(_ id: String?) {
        UserDefaults.standard.set(id, forKey: "lastNotified_\(conversationId)")
    }
}
