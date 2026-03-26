////
////  SupabaseClusterRow.swift
////  Locolo
////
////  Created by Apramjot Singh on 3/11/2025.
////
//
//import Foundation
//
///// Decodable row returned from get_assets_for_view RPC
///// Mirrors the SQL function return type exactly
//struct SupabaseClusterRow: Codable {
//    let kind: String              // 'cluster' | 'point'
//    let cluster_id: Int64?        // cluster id (null for point)
//    let asset_id: UUID?           // asset id (null for cluster)
//    let name: String?
//    let user_id: UUID?
//    let location_id: UUID?
//    let file_url: String?
//    let thumb_url: String?
//    let file_type: String?
//    let category: String?
//    let description: String?
//    let hype_count: Int?
//    let view_count: Int?
//    let created_at: Date?
//    let panorama_url: String?
//    let visibility: String?
//    let interaction_type: String?
//    let location_name: String?
//    let latitude: Double?
//    let longitude: Double?
//    let count: Int?
//    let member_ids: [UUID]?
//    
//    /// Convert to ClusterNode
//    func toClusterNode() -> ClusterNode? {
//        guard let lat = latitude, let lon = longitude else { return nil }
//        
//        if kind == "cluster" {
//            return ClusterNode(
//                id: "cluster:\(cluster_id ?? -1)",
//                kind: kind,
//                clusterId: cluster_id,
//                asset: nil,
//                latitude: lat,
//                longitude: lon,
//                count: count ?? 1,
//                memberIds: member_ids ?? []
//            )
//        } else {
//            guard let assetId = asset_id,
//                  let fileUrl = file_url,
//                  let fileType = file_type,
//                  let vis = visibility,
//                  let userId = user_id,
//                  let createdAt = created_at else {
//                return nil
//            }
//            
//            let asset = DigitalAsset(
//                id: assetId,
//                name: name,
//                userId: userId,
//                locationId: location_id,
//                fileUrl: fileUrl,
//                thumbUrl: thumb_url,
//                fileType: fileType,
//                category: category,
//                description: description,
//                hypeCount: hype_count ?? 0,
//                viewCount: view_count ?? 0,
//                createdAt: createdAt,
//                panoramaUrl: panorama_url,
//                visibility: vis,
//                interactionType: interaction_type,
//                locationName: location_name,
//                latitude: lat,
//                longitude: lon,
//                
//            )
//            
//            return ClusterNode(
//                id: "asset:\(assetId.uuidString)",
//                kind: kind,
//                clusterId: nil,
//                asset: asset,
//                latitude: lat,
//                longitude: lon,
//                count: 1,
//                memberIds: [assetId]
//            )
//        }
//    }
//}
//
