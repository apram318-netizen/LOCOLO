//
//  NotificationRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 14/11/2025.
//
//  This file handles all the Firestore reads for user notifications.
//  Basically: real-time streams of notifications + initial loads + marking notifications as read.


import FirebaseFirestore

final class NotificationRepository {
    private let db = Firestore.firestore()

    
    // MARK: FUNCTION: listenUserNotifications
    /// - Description:
    ///   Live stream of all notifications for a given user.
    ///   This is the pure listener-only  version  no initial fetch is being used
    ///
    ///   Whenever Firestore updates, the stream gives the latest list.
    ///
    /// - Parameter userId: The current user's ID
    /// - Returns: AsyncStream<[AppNotification]> that UI can subscribe to
    func listenUserNotifications(userId: String) -> AsyncStream<[AppNotification]> {
        AsyncStream { continuation in

            let listener = db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { snapshot, error in

                    if let error = error {
                        print(" Firestore notify error:", error)
                        continuation.yield([])
                        return
                    }

                    let notifs = snapshot?.documents.compactMap {
                        try? $0.data(as: AppNotification.self)
                    } ?? []

                    continuation.yield(notifs)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }


    
    // MARK: FUNCTION: fetchAndListenUserNotifications
    /// - Description:
    ///   Same as listenUserNotifications, but this version does a one-time fetch first.
    ///   This helps when the notifications screen loads  you avoid the “empty flash”
    ///   before the snapshot listener fires.
    ///
    func fetchAndListenUserNotifications(userId: String) -> AsyncStream<[AppNotification]> {
        AsyncStream { continuation in

            // STEP 1 – Initial fetch (await)
            Task {
                do {
                    let snapshot = try await db.collection("notifications")
                        .whereField("userId", isEqualTo: userId)
                        .order(by: "timestamp", descending: true)
                        .getDocuments()

                    let initial = snapshot.documents.compactMap {
                        try? $0.data(as: AppNotification.self)
                    }
                    continuation.yield(initial)

                } catch {
                    print(" Initial notification fetch error:", error)
                    continuation.yield([])
                }
            }

            // STEP 2 – Live updates
            let listener = db.collection("notifications")
                .whereField("userId", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { snapshot, error in

                    if let error = error {
                        print(" Snapshot notify error:", error)
                        continuation.yield([])
                        return
                    }

                    let notifs = snapshot?.documents.compactMap {
                        try? $0.data(as: AppNotification.self)
                    } ?? []

                    continuation.yield(notifs)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }


    
    // MARK: FUNCTION: markAsRead
    /// - Description:
    ///   Updates a notification’s read  flag.
    ///   This does not throw or break anything if the write fails
    ///
    /// - Parameter id: Firestore document ID of the notification
    func markAsRead(_ id: String) async {
        let ref = db.collection("notifications").document(id)
        try? await ref.updateData(["read": true])
    }
}
