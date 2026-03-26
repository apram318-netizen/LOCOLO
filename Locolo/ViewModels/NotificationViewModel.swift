//
//  NotificationViewModel.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//
//  This file manages all app notifications for the user.
//  It listens to Firestore in real time and updates the UI.
//  It also has a few good helper functions that helps to filter notifications by type.
//  Notifications are split into general and digital art.


import Foundation

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var selectedTab: String = "General"

    private let repo = NotificationRepository()
    private var userId: String

    /// - Description: Stores the user id and opens a live Firestore listener.
    init(userId: String) {
        self.userId = userId
        startListening()
    }

    /// - Description: Starts the async stream from Firestore.
    ///   Each new snapshot replaces the current notifications list.
    private func startListening() {
        Task {
            for await notifs in repo.fetchAndListenUserNotifications(userId: userId) {
                self.notifications = notifs
            }
        }
    }

    /// - Description: Marks a notification as read in Firestore.
    /// - Parameters: notif is the notification to update.
    func markRead(_ notif: AppNotification) {
        guard let id = notif.id else { return }
        Task { await repo.markAsRead(id) }
    }

    /// - Description: Returns all notifications that are not tagged as digital art.
    var generalNotifs: [AppNotification] {
        notifications.filter { $0.type != "digital_art" }
    }

    /// - Description: Returns digital art related notifications only.
    var artNotifs: [AppNotification] {
        notifications.filter { $0.type == "digital_art" }
    }
}

extension Date {
    /// - Description: Turns a date into a short time-ago string.
    ///   Example: "2h ago", "5m ago".
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
