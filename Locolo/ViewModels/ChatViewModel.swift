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
    /// key when available. Before the key resolves we surface the raw body so
    /// legacy/plaintext conversations still read.
    private func applyDecryption() {
        messages = rawMessages.map { message in
            var copy = message
            if let key = conversationKey {
                copy.decryptedText = CryptoService.shared.open(message.text, key: key)
            } else {
                copy.decryptedText = message.text
            }
            return copy
        }
    }

    // MARK: FUNCTION: startListening
    private func startListening() {
        listenerTask = Task {
            for await newMessages in repo.listenMessages(conversationId: conversationId, forUser: userId) {
                await MainActor.run {
                    self.rawMessages = newMessages
                    self.applyDecryption()

                    // Notify on a new incoming message (payload is ciphertext).
                    if let last = newMessages.last, last.senderId != self.userId,
                       last.id != self.getLastNotifiedId() {
                        self.setLastNotifiedId(last.id)
                        NotificationManager.shared
                            .showInAppNotification(for: last, conversationId: self.conversationId)
                    }
                }
            }
        }
    }

    // MARK: FUNCTION: sendMessage
    /// Encrypts the body (when a key is available) and sends ciphertext, with a
    /// privacy-preserving conversation preview. Falls back to plaintext only if
    /// the peer hasn't published a key yet.
    func sendMessage(_ text: String, senderId: String, senderName: String) {
        Task {
            let bodyToStore: String
            let preview: String?
            if let key = conversationKey, let sealed = try? CryptoService.shared.seal(text, key: key) {
                bodyToStore = sealed
                preview = "🔒 Encrypted message"
            } else {
                bodyToStore = text
                preview = nil
            }

            let msg = Message(
                senderId: senderId.lowercased(),
                senderName: senderName,
                text: bodyToStore,
                time: Date()
            )
            try? await repo.sendMessage(conversationId: conversationId, message: msg, lastMessagePreview: preview)
        }
    }

    private func getLastNotifiedId() -> String? {
        UserDefaults.standard.string(forKey: "lastNotified_\(conversationId)")
    }

    private func setLastNotifiedId(_ id: String?) {
        UserDefaults.standard.set(id, forKey: "lastNotified_\(conversationId)")
    }
}
