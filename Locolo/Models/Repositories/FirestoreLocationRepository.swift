//
//  FirestoreLocationRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//

import CoreLocation
import FirebaseFirestore

final class FirestoreLocationRepository: LocationRepositoryProtocol {
    
    func uploadVisit(_ visit: CLVisit) {
        //Repository Function
    }
    
    func reconcileResidencyIfNeeded() async {
        //Repository Function
    }
    
    
    private let db = Firestore.firestore()

    
    // MARK: FUNCTION: uploadPings
    /// - Description: Uploads a batch of location pings to Firestore all at once.
    /// Wraps everything in a batch write so it’s quick and atomic , either all go up or none do.
    /// Usually called when background location tracking pushes multiple points together.
    ///
    /// - Parameter pings: An array of `LocationPing` objects containing coordinates, speed, accuracy, and timestamp
    /// - Throws: If the Firestore batch commit fails
    func uploadPings(_ pings: [LocationPing]) async throws {
        let batch = db.batch()
        let ref = db.collection("user_locations")

        for ping in pings {
            let doc = ref.document()
            batch.setData([
                "lat": ping.latitude,
                "lon": ping.longitude,
                "speed": ping.speed,
                "accuracy": ping.accuracy,
                "timestamp": Timestamp(date: ping.timestamp)
            ], forDocument: doc)
        }
        try await batch.commit()
    }
    
    
}
