//
//  LocationRepositoryProtocol.swift
//  Locolo
//
//  Created by Apramjot Singh on 8/11/2025.
//

import CoreLocation


protocol LocationRepositoryProtocol {
    
    func uploadPings(_ pings: [LocationPing]) async throws
    func uploadVisit(_ visit: CLVisit)
    func reconcileResidencyIfNeeded() async
}
