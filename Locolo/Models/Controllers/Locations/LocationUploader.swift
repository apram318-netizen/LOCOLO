//
//  LocationUploader.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//

import Foundation
import CoreLocation
import FirebaseFirestore

final class LocationUploader {
    static let shared = LocationUploader()
    private let db = Firestore.firestore()
    private let supabase = SupabaseManager.shared
    private let locationManager = CLLocationManager()
    private init() {}

    // ---- Residency constants ----
    private let reconciliationThresholdHours: Double = 10 // run every 10 h

   
    // MARK: FUNCTION: Regular ping uploads (uses Supabase user ID)
    /// - Description: This takes in the user's location and then uploads to the firebase users  collection
    ///
    /// This function even though it uploads to firebase it still uses the supbase user id to authenticate the stored firebase user
    ///
    /// - Parameter location: Takes in the CLLocation
    /// - Returns: Nothing
    func uploadPing(_ location: CLLocation) {
        
        guard let supabaseId = SupabaseManager.shared.currentUserId?.lowercased() else {
            print(" No Supabase user found — skipping ping upload.")
            return
        }
        
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        
        UserDefaults.standard.set(["lat": lat, "lon": lon, "timestamp": Date().timeIntervalSince1970], forKey: "latestUserLocation")
        
        
        let data: [String: Any] = [
            "geo": GeoPoint(latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude),
            "timestamp": FieldValue.serverTimestamp(),
            "speed": location.speed,
            "accuracy": location.horizontalAccuracy
        ]
        
        //  Overwrite current location
        db.collection("users")
            .document(supabaseId)
            .collection("current_location")
            .document("latest")
            .setData(data, merge: true) { err in
                if let err = err {
                    print(" Failed to update current location: \(err)")
                } else {
                    print(" Updated live location for \(supabaseId)")
                }
            }
        
        //  Append to history
        db.collection("users")
            .document(supabaseId)
            .collection("location_history")
            .addDocument(data: data) { err in
                if let err = err {
                    print(" Failed to append to history: \(err)")
                } else {
                    print(" Added history point for \(supabaseId)")
                }
            }
        
        Task {
            guard let coord = LocationManager.shared.latestStoredLocation,
                  let userId = SupabaseManager.shared.currentUserId else { return }

            do {
                let nearby = try await PlacesRepository().checkNearbyPlaces(
                    lat: coord.latitude,
                    lon: coord.longitude,
                    radiusMeters: 150
                )

                if nearby.isEmpty {
                    print(" No nearby Locolo places — skipping visit flow.")
                    return
                }

                print(" \(nearby.count) nearby places found → checking visits…")
                await VisitMonitor.shared.performVisitCheck(using: nearby)   // <— PASS SNAPSHOT
            } catch {
                print(" Nearby place check failed:", error)
            }
        }
    }
    
    

    // MARK: FUNCTION: uploadVisit
    /// - Description: Uploads the visit to firebase by logging the arival
    ///
    /// This function is probably not in use anymore or relevant: May take it out later.
    ///
    /// - Parameter visit: Takes in the CLVisit
    /// - Returns: Nothing
    func uploadVisit(_ visit: CLVisit) {
        guard let supabaseId = SupabaseManager.shared.currentUserId?.lowercased()  else {
            print(" No Supabase user found — skipping visit upload.")
            return
        }

        var data: [String: Any] = [
            "geo": GeoPoint(latitude: visit.coordinate.latitude,
                            longitude: visit.coordinate.longitude)
        ]

        if visit.arrivalDate != .distantPast {
            data["arrival"] = Timestamp(date: visit.arrivalDate)
        }
        if visit.departureDate != .distantFuture {
            data["departure"] = Timestamp(date: visit.departureDate)
        }

        db.collection("users")
            .document(supabaseId)
            .collection("visits")
            .addDocument(data: data) { err in
                if let err = err {
                    print(" Visit upload failed: \(err)")
                } else {
                    print(" Logged visit for \(supabaseId)")
                }
            }
    }
    

   
    // MARK: FUNCTION: Residency reconciliation check (runs every 10 h)
    /// - Description: This function maintains the whole flow and checks if its been more than 10h since we last checked the locations log
    ///
    /// THis is also checking things like location permissions and user id etc, In case of any reconcilation fails try  checking the output log
    func reconcileIfNeeded() async {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            print(" Location permission denied — skipping reconciliation.")
            return
        }

        guard let supabaseId = SupabaseManager.shared.currentUserId?.lowercased()  else {
            print(" No Supabase user logged in.")
            return
        }

        let defaultStart = Date().addingTimeInterval(-10 * 3600) // last 10 hours
        let lastCheck = UserDefaults.standard.object(forKey: "lastResidencyCheck") as? Date ?? defaultStart

        let hoursSince = Date().timeIntervalSince(lastCheck) / 3600.0
        guard hoursSince >= reconciliationThresholdHours else {
            print(" Residency reconciliation skipped — only \(hoursSince) h since last run.")
            return
        }

        do {
            try await reconcileResidency(for: supabaseId, since: lastCheck)
            UserDefaults.standard.set(Date(), forKey: "lastResidencyCheck")
            print(" Residency reconciliation complete.")
        } catch {
            print(" Residency reconciliation failed: \(error)")
        }
    }
    

    // MARK: FUNCTION: Residency reconciliation
    /// - Description: Gets the location history from firestore and checks the time user stayed at the places
    /// - Parameters : - userId: The supabase user id - since: the llast time you want to reconcile for
    /// - Returns: nil
    ///
    /// this function is using the location pings uploaded to firebase and is calculating the difference in the change
    /// this assumes that if the location hasnt updated that is because the user is still at the same place
    ///
    /// Tis function neems some scoldings and limits.. IT is using too many pings at the moment if user travelled a lot.
    /// If this app becomes famous then make sure that this function uses 2-3 pings only for each hour. Too many function calls currently
    /// ps: I need it as it is for now.
    ///
    private func reconcileResidency(for userId: String, since date: Date) async throws {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("location_history")
            .whereField("timestamp", isGreaterThan: Timestamp(date: date))
            .order(by: "timestamp", descending: false)
            .getDocuments()

        let docs = snapshot.documents
        guard docs.count > 1 else {
            print(" Not enough pings to process.")
            return
        }

        let pings: [UserPing] = docs.compactMap { doc in
            guard let geo = doc.get("geo") as? GeoPoint,
                  let ts = doc.get("timestamp") as? Timestamp else { return nil }
            return UserPing(latitude: geo.latitude,
                            longitude: geo.longitude,
                            timestamp: ts.dateValue(),
                            speed: doc.get("speed") as? Double ?? 0)
        }

        var loopDurations: [UUID: Double] = [:]

        for (prev, next) in zip(pings, pings.dropFirst()) {
            let durationHours = next.timestamp.timeIntervalSince(prev.timestamp) / 3600.0
            guard durationHours > 0 else { continue }

            let prevLoop = try await supabase.findLoop(forLat: prev.latitude, lon: prev.longitude)
            let nextLoop = try await supabase.findLoop(forLat: next.latitude, lon: next.longitude)

            if prevLoop == nextLoop, let loopId = nextLoop {
                loopDurations[loopId, default: 0] += durationHours
            } else if let prevId = prevLoop {
                try await supabase.markUserLeftLoop(userId: userId, loopId: prevId)
            }
        }

        if let lastPing = pings.last,
           let lastLoop = try? await supabase.findLoop(forLat: lastPing.latitude, lon: lastPing.longitude) {
            let offlineHours = Date().timeIntervalSince(lastPing.timestamp) / 3600.0
            if offlineHours > 0 {
                loopDurations[lastLoop, default: 0] += offlineHours
            }
        }

        for (loopId, hours) in loopDurations {
            print(" Adding \(hours )h to loop \(loopId)")
            try await supabase.updateLoopCounter(userId: userId, loopId: loopId, hours: hours)
        }
    }
    
    
}




// MARK: - Helper Struct
// Just using it to help with basic firebase upload mapping
private struct UserPing {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speed: Double
}

