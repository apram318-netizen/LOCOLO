//
//  NotificationService.swift
//  LocoloNotificationService
//
//  Created by Apramjot Singh on 13/11/2025.
//

import UserNotifications
import Foundation


class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            return contentHandler(request.content)
        }

        // 1. Set category to enable inline Reply
        bestAttemptContent.categoryIdentifier = "CHAT_MESSAGE"

        // 2. Extract custom chat data (from Firestore/Supabase function)
        let userInfo = request.content.userInfo

        let senderName = userInfo["senderName"] as? String
        let messageText = userInfo["message"] as? String

        // 3. Update title & body cleanly
        if let senderName {
            bestAttemptContent.title = senderName
        }

        if let messageText {
            bestAttemptContent.body = messageText
        }

        // Chat is end-to-end encrypted and this extension has no access to the
        // app's Keychain identity key, so it can't decrypt. Never surface the
        // base64 ciphertext on the lock screen.
        if Self.looksLikeCiphertext(bestAttemptContent.body) {
            bestAttemptContent.body = "🔒 New encrypted message"
        }

        // 4. OPTIONAL: Add badge / sound
        bestAttemptContent.sound = .default

        // 5. Deliver modified notification
        contentHandler(bestAttemptContent)
    }

    
    /// AES-GCM combined box = 12-byte nonce + ciphertext + 16-byte tag, base64.
    private static func looksLikeCiphertext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40, !trimmed.contains(" "),
              let data = Data(base64Encoded: trimmed) else { return false }
        return data.count >= 28
    }

    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
    


}
