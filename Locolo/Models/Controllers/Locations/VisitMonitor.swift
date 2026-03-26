//
//  VisitMonitor.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//

import Foundation
import CoreLocation
import UserNotifications
import FirebaseFirestore

@MainActor
final class VisitMonitor: ObservableObject {
    static let shared = VisitMonitor()
    private let repo = VisitRepository()
    private let placesRepo = PlacesRepository()
    private let radius: Double = 150

    
    // MARK: FUNCTION: Visit Check
    /// - Description : It fetches the current user coordinates and supabase current user visits and writes and updates visits to supabase accoordingly
    ///
    /// So, when reading from  the supabase it just simply uses the info to access when we first arrived here and if its been more than 10 mins or not , if it is more than 10
    ///and we are still here, this means we have explored a new place and we confirm the visit. Else we just wait for 10 minutes
    ///
    ///In future, I wanna change the functionality for the 1 hour or more visit to check the logs if user left or not, instead of just refreshing the visit
    ///
    func performVisitCheck(using nearby: [Place]? = nil) async {
        guard let coord = LocationManager.shared.latestStoredLocation,
              let userStr = SupabaseManager.shared.currentUserId,
              let userId = UUID(uuidString: userStr) else {
            print(" Missing user or stored location.")
            return
        }

        do {
            // If we already HAVE a snapshot from uploadPing → use it
            // Otherwise fetch normally (keeps backward compatibility)
            let places = try await placesRepo.checkNearbyPlaces(
                lat: coord.latitude,
                lon: coord.longitude,
                radiusMeters: radius
            )

            print(" Found \(places.count) nearby places")

            for place in places {
                
                // Already have a visit entry?
                if let visit = try await repo.getVisit(userId: userId, placeId: place.id) {
                    
                    // Visit exists but not yet confirmed?
                    if visit.visitConfirmed != true {
                        let elapsed = Date().timeIntervalSince(visit.startedAt ?? Date())
                        let userLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        let placeLocation = CLLocation(latitude: place.location?.latitude ?? 0, longitude: place.location?.longitude ?? 0)
                        let distance = userLocation.distance(from: placeLocation)

                        if elapsed < 600 {
                            if distance >= 150 {
                                await repo.resetVisit(userId: userId, placeId: place.id)
                                continue
                            }
                            print("<10 min near \(place.name) → waiting.")
                            continue
                        }

                        // 10 min ≤ elapsed < 1 hour → Confirm visit
                        if elapsed >= 600 && elapsed < 3600 {
                            await repo.confirmVisit(userId: userId, placeId: place.id)

                            //  KEEP NOTIFICATION
                            sendNotification(
                                title: "Added to Explored!",
                                body: "\(place.name) has been added to your explored places."
                            )

                            //  KEEP FIRESTORE LOGGING
                            Task {
                                do {
                                    let db = Firestore.firestore()
                                    let log: [String: Any] = [
                                        "userId": SupabaseManager.shared.currentUserId ?? "unknown",
                                        "title": "Added to Explored!",
                                        "body": "\(place.name) has been added to your explored places.",
                                        "type": "visit_event",
                                        "timestamp": FieldValue.serverTimestamp(),
                                        "read": false
                                    ]
                                    try await db.collection("notifications").addDocument(data: log)
                                    print(" Visit notification logged to Firestore")
                                } catch {
                                    print(" Failed logging notification:", error)
                                }
                            }

                        // 1h+ → Reset visit timer
                        } else if elapsed >= 3600 {
                            await repo.resetVisit(userId: userId, placeId: place.id)
                        }
                    }

                // No visit found yet → Create a new visit entry
                } else {
                    await repo.createVisit(userId: userId, placeId: place.id)

                    //  KEEP NOTIFICATION
                    sendNotification(
                        title: "Exploring \(place.name)?",
                        body: "Stay here for 10 minutes to mark it as explored."
                    )
                }
            }

        } catch {
            print(" Visit check failed:", error)
        }
    }

    

    // MARK: FUNCTION: sendNotification
    /// - Description : Sends notifications to the user taking in the title and string
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
    
}
