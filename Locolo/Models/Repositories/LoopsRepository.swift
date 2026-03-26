//
//  LoopsRepository.swift
//  Locolo
//
//  Created by Apramjot Singh on 17/9/2025.
//
import Foundation
import CoreLocation
import Supabase
import SwiftUI


// Description: Simple wrapper to encode polygon or multipolygon data for Supabase/PostGIS.
struct GeoJSONGeometry: Codable {
    let type: String
    let coordinates: [[[[Double]]]]
    
    init(polygonRings: [[[Double]]]) {
        self.type = "MultiPolygon"
        self.coordinates = [polygonRings]
    }
    
    init(polygons: [[[[Double]]]]) {
        self.type = "MultiPolygon"
        self.coordinates = polygons
    }
}


struct LoopOverlapResult: Decodable, Identifiable {
    let conflict_loop_id: UUID
    let conflict_name: String
    
    var id: UUID { conflict_loop_id }
    var name: String { conflict_name }
}



struct CreateLoopPayload: Encodable {
    let name: String
    let description: String?
    let coverImageUrl: String?
    let locationName: String
    let latitude: Double
    let longitude: Double
    let memberCount: Int
    let isMember: Bool
    let isActive: Bool
    let loopType: String
    let boundary: GeoJSONGeometry?
    let boundaryRaw: GeoJSONGeometry
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case coverImageUrl = "cover_image_url"
        case locationName = "location_name"
        case latitude
        case longitude
        case memberCount = "member_count"
        case isMember = "is_member"
        case isActive = "is_active"
        case loopType = "loop_type"
        case boundary
        case boundaryRaw = "boundary_raw"
    }
}

private struct LoopOverlapParams: Encodable {
    let p_geojson: GeoJSONGeometry
    let p_lat: Double
    let p_lon: Double
    let p_radius_km: Double
}

/// used for creating a new loop in Supabase.
private struct UniversityDuplicateParams: Encodable {
    let p_lat: Double
    let p_lon: Double
    let p_name: String
    let p_radius_m: Double
}

/// used for creating a new loop in Supabase.
private struct UniversityDuplicateResult: Decodable {
    let loop_id: UUID
}


/// So, the main place that talks to Supabase about anything loop-related
/// whether that’s checking overlaps, duplicates, or adding a new one.
class LoopsRepository: LoopRepositoryProtocol {
    
    private let client = SupabaseManager.shared.client

    // MARK: FUNCTION: fetchUserLoops
    /// - Description: Loads all loops visible to the user, ordered by creation date (newest first).
    /// - Parameter completion: A closure returning a `Result` with `[Loop]` on success or `Error` on failure.
    func fetchUserLoops(completion: @escaping (Result<[Loop], Error>) -> Void) {
        Task {
            do {
                let loops: [Loop] = try await client
                    .from("loops")
                    .select("id,name,description,cover_image_url,location_name,latitude,longitude,member_count,is_member,is_active,loop_type")
                    .order("created_at", ascending: false)
                    .execute()
                    .value
                completion(.success(loops))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    

    // MARK: FUNCTION: searchLoops
    /// - Description: Searches loops by keyword, matching loop names case-insensitively.
    /// - Parameters:
    ///   - query: The text to search for in loop names.
    ///   - completion: Closure returning `[Loop]` if found or an error if not.
    func searchLoops(query: String, completion: @escaping (Result<[Loop], Error>) -> Void) {
        Task {
            do {
                let loops: [Loop] = try await client
                    .from("loops")
                    .select("id,name,description,cover_image_url,location_name,latitude,longitude,member_count,is_member,is_active,loop_type")
                    .ilike("name", pattern: "%\(query)%")
                    .limit(25)
                    .execute()
                    .value
                completion(.success(loops))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    

    // MARK: FUNCTION: checkLoopOverlap
    /// - Description: Checks if a new loop’s area overlaps with any existing ones.
    /// - Parameters:
    ///   - center: The loop’s central coordinates.
    ///   - boundary: The loop’s boundary in GeoJSON format.
    /// - Returns: A list of `LoopOverlapResult` items if any conflicts are found.
    func checkLoopOverlap(center: CLLocationCoordinate2D, boundary: GeoJSONGeometry) async throws -> [LoopOverlapResult] {
        let params = LoopOverlapParams(
            p_geojson: boundary,
            p_lat: center.latitude,
            p_lon: center.longitude,
            p_radius_km: 150
        )
        return try await client
            .rpc("loops_check_overlap", params: params)
            .execute()
            .value
    }

    
    
    // MARK: FUNCTION: hasUniversityDuplicate
    /// - Description: Checks if a university-type loop already exists nearby.
    /// - Parameters:
    ///   - center: The coordinates of the proposed university loop.
    ///   - name: The name of the university loop.
    /// - Returns: `true` if a duplicate exists nearby, otherwise `false`.
    func hasUniversityDuplicate(center: CLLocationCoordinate2D, name: String) async throws -> Bool {
        let params = UniversityDuplicateParams(
            p_lat: center.latitude,
            p_lon: center.longitude,
            p_name: name,
            p_radius_m: 250
        )
        let result: [UniversityDuplicateResult] = try await client
            .rpc("loops_check_university_duplicate", params: params)
            .execute()
            .value
        return !result.isEmpty
    }
    
    

    // MARK: FUNCTION: createLoop
    /// - Description: Creates a new loop entry in Supabase with all required metadata and boundary.
    /// - Parameter payload: A `CreateLoopPayload` object with name, type, boundary, and location info.
    /// - Throws: If the Supabase insert fails.
    func createLoop(payload: CreateLoopPayload) async throws {
        try await client
            .from("loops")
            .insert(payload)
            .select()
            .execute()
    }
    
    
    
    // MARK: FUNCTION: fetchLoopTag
    /// - Description: THis function queries the supabase and just returns an optional string tag
    /// - Parameters:
    ///   - userId: Active user's supabase id
    ///   - loopId: current active loop
    /// - Returns:An optional string
    func fetchLoopTag(userId: UUID, loopId: UUID) async throws -> String? {
        let rows: [LoopTimeCounterRow] = try await client
            .from("loop_time_counters")
            .select("*")
            .eq("user_id", value: userId.uuidString.lowercased())
            .eq("loop_id", value: loopId.uuidString.lowercased())
            .execute()
            .value

        return rows.first?.status
    }
    
    
    
    // MARK: FUNCTION: fetchLoopTag
    /// - Description: This functions compresses the image to 0.5 and uploads the cover image returning a url string
    ///
    /// currently the supabase image is under the limit of 1 mb and compressing the cover image to 0.5 mb is thee safest option currently.
    ///
    /// - Parameter image : UI Image that the user wants to upload
    /// - Returns:A string
    func uploadLoopCoverImage(_ image: UIImage) async throws -> String {
        // Target: ≤ 0.5 MB (500 KB)
        let maxFileSize: Int = 500 * 1024
        
        // Start at decent quality and shrink as needed
        var compression: CGFloat = 0.8
        var imageData = image.jpegData(compressionQuality: compression)
        
        // If image too large, keep scaling down quality until under 0.5 MB
        while let data = imageData, data.count > maxFileSize, compression > 0.1 {
            compression -= 0.1
            imageData = image.jpegData(compressionQuality: compression)
        }
        
        // If still too large (e.g. very high-resolution image), scale down dimensions
        if let data = imageData, data.count > maxFileSize {
            let targetWidth: CGFloat = 1200
            let scale = targetWidth / image.size.width
            let newSize = CGSize(width: targetWidth, height: image.size.height * scale)
            
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
            
            // Re-compress resized image
            imageData = resized.jpegData(compressionQuality: 0.6)
        }
        
        guard let finalData = imageData else {
            throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
        }
        
        // Upload to Supabase Storage
        let fileName = "covers/\(UUID().uuidString).jpg"
        return try await ObjStorageManager.shared.uploadFile(
            bucket: "loops",
            path: fileName,
            fileData: finalData,
            contentType: "image/jpeg"
        )
    }


}


struct LoopTimeCounterRow: Identifiable, Codable {
    let id: UUID?
    let userId: UUID?
    let loopId: UUID?
    let totalHours: Double?
    let firstArrivedAt: String?
    let lastArrivedAt: String?
    let status: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case loopId = "loop_id"
        case totalHours = "total_hours"
        case firstArrivedAt = "first_arrived_at"
        case lastArrivedAt = "last_arrived_at"
        case status
        case updatedAt = "updated_at"
    }
}
