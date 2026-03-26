//
//  NotificationManager.swift
//  Locolo
//
//  Created by Apramjot Singh on 13/11/2025.
//

import UserNotifications
import Firebase
import Foundation

/// okay so this thing handles *literally everything* notifications.
/// push, in-app, replying straight from the banner, all of it.
/// kinda like the postman for Locolo.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    
    static let shared = NotificationManager()
    private override init() {}   // singleton vibes
    
    // MARK: - Permission Stuff
    /// asking the user for notification permission bc apple won't let us just do things quietly.
    /// also sets up the "reply" button in the notification banner (the little textbox)
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // setting up that quick-reply-from-banner thing
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..." // like i'm ever typing more than “ok”
        )

        // this is the category used for chat notifications
        let chatCategory = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([chatCategory])

        // the actual permission popup
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("Notification permission error:", error) }
            print("Notifications granted:", granted)
        }

        // this registers device with APNs
        UIApplication.shared.registerForRemoteNotifications()
    }

    
    
    // MARK: - Handle taps + replies on notifications
    /// this fires when the user *interacts* with a notification
    /// (taps it, replies, etc)
    ///
    /// basically: if user hits the “reply” action → we catch the text here and send it
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {

        let userInfo = response.notification.request.content.userInfo

        // if user used the quick reply box
        if response.actionIdentifier == "REPLY_ACTION",
           let reply = (response as? UNTextInputNotificationResponse)?.userText,
           let convoId = userInfo["conversationId"] as? String,
           let senderName = userInfo["senderName"] as? String {
            
            // fire off a background send
            Task {
                let currentUserId = SupabaseManager.shared.currentUserId ?? ""
                
                // loading the chat VM for this convo
                let vm = ChatViewModel(conversationId: convoId, userId: currentUserId)
                
                // send message with basic metadata
                vm.sendMessage(reply, senderId: currentUserId, senderName: senderName)
            }
        }

        completionHandler()
    }

    

    // MARK: - Foreground presentation
    /// when the app is open and a notif comes → we decide how dramatic to be.
    /// i always want the banner + sound (why would i hide my own app from myself???)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

        completionHandler([.banner, .sound])   // show it even if you're inside the app
    }
    

    
    // MARK: - In-app fake notification
    /// sometimes we want to show a notification inside the app
    /// like if you're already in a chat but still want that  pop-up
    ///
    /// so this manually creates a local notification (no APNs here)
    func showInAppNotification(for message: Message, conversationId: String) {
        
        let content = UNMutableNotificationContent()
        content.title = message.senderName      // who messaged
        content.body = message.text            // the message
        content.sound = .default
        content.categoryIdentifier = "CHAT_MESSAGE"
        content.userInfo = [
            "conversationId": conversationId,
            "senderName": message.senderName
        ]

        // trigger: nil = show immediately
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,  // unique id bc ofc it needs one
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}




// MARK: - Track “already notified” messages
/// storing what last message id got a notification
/// so we don’t spam notif for old messages when loading chat history
///
/// literally just stored in UserDefaults because it makes things easier.
struct NotifiedMessageTracker {
    
    static func getLastNotifiedMessageId(for conversationId: String) -> String? {
        UserDefaults.standard.string(forKey: "lastNotified_\(conversationId)")
    }

    static func setLastNotifiedMessageId(_ messageId: String, for conversationId: String) {
        UserDefaults.standard.set(messageId, forKey: "lastNotified_\(conversationId)")
    }
}
