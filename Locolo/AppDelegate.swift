//
//  AppDelegate.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//


import UIKit
import CoreLocation

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
       
        
        // 2. Register notification actions/categories
          //configureNotificationActions()
        
        // 3. Request notification permissions
        //requestNotificationPermissions()
        
        if launchOptions?[.location] != nil {
            print(" Relaunched by iOS due to significant location change")
            _ = LocationManager.shared
        }
        
        return true
    }
    
    
    
    private func configureNotificationActions() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: []
        )
        
        let chatCategory = UNNotificationCategory(
            identifier: "CHAT_MESSAGE",
            actions: [replyAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([chatCategory])
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                print("Notifications permitted")
            } else {
                print("Notification permission denied", error ?? "")
            }
        }
    }
    
    
    // MARK: Handle inline notification reply
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Check if the user pressed Reply
        if response.actionIdentifier == "REPLY_ACTION",
           let textResponse = response as? UNTextInputNotificationResponse {

            let replyText = textResponse.userText

            print("User replied: \(replyText)")

            // Send reply to your chat system
            if let convoId = userInfo["conversationId"] as? String,
               let senderId = userInfo["receiverId"] as? String,      // your user
               let senderName = userInfo["receiverName"] as? String { // your username
                
                Task {
                    try? await ChatRepository().sendMessage(
                        conversationId: convoId,
                        message: Message(
                            senderId: senderId,
                            senderName: senderName,
                            text: replyText,
                            time: Date()
                        )
                    )
                }
            }
        }

        completionHandler()
    }
    
}


