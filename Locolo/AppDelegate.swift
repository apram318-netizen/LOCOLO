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
        // Inline replies are handled by NotificationManager (the registered
        // delegate), which encrypts before sending. Never write chat messages
        // from here: a raw ChatRepository send would store plaintext.
        completionHandler()
    }
    
}


