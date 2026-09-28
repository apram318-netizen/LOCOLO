//
//  AssetShareService.swift
//  Locolo
//
//  Instagram-style "send this asset in a message". A shared asset is just an
//  ordinary chat message whose plaintext is the asset's deep link
//  (locolo://asset/<id>) — so it flows through the exact same E2E-encrypted
//  pipeline as any message (no new crypto path, no schema change). The chat
//  renderer detects the link and shows a rich card instead of text.
//

import Foundation

@MainActor
final class AssetShareService {
    static let shared = AssetShareService()
    private let chat = ChatRepository()
    private init() {}

    /// Find-or-create the 1:1 conversation with `peer`, then send `assetId` as
    /// an (encrypted) asset-share message. Returns whether it sent.
    @discardableResult
    func shareAsset(_ assetId: UUID, to peer: UUID, from me: User) async -> Bool {
        let myId = me.id.uuidString.lowercased()
        let peerId = peer.uuidString.lowercased()

        let convoId: String
        if let existing = (try? await chat.findExistingConversation(between: myId, and: peerId)) ?? nil {
            convoId = existing
        } else if let created = try? await chat.createConversation(between: [myId, peerId]) {
            convoId = created
        } else {
            return false
        }

        // Reuse ChatViewModel so the message is encrypted with the same
        // conversation-key logic as a normal send.
        let vm = ChatViewModel(conversationId: convoId, userId: myId, peerId: peer)
        let link = DeepLinkRouter.assetURL(for: assetId).absoluteString
        return await vm.sendMessage(link, senderId: myId, senderName: me.name ?? me.username)
    }
}
