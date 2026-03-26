//
//  LoopRepositoryProtocol.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//


import SwiftUI
import Foundation
import CoreLocation

protocol LoopRepositoryProtocol {
    func fetchUserLoops(completion: @escaping (Result<[Loop], Error>) -> Void)
    func searchLoops(query: String, completion: @escaping (Result<[Loop], Error>) -> Void)
    func checkLoopOverlap(center: CLLocationCoordinate2D, boundary: GeoJSONGeometry) async throws -> [LoopOverlapResult]
    func createLoop(payload: CreateLoopPayload) async throws
    func hasUniversityDuplicate(center: CLLocationCoordinate2D, name: String) async throws -> Bool
    func fetchLoopTag(userId: UUID, loopId: UUID) async throws -> String?
    
    func uploadLoopCoverImage(_ image: UIImage) async throws -> String
    
}
