//
//  ClusterNode.swift
//  Locolo
//
//  Created by Apramjot Singh on 3/11/2025.
//

import Foundation

/// Unified model representing either a cluster or individual point on the map
struct ClusterNode: Identifiable, Codable {
    let id: String           // "cluster:<id>" or "asset:<uuid>"
    let kind: String         // "cluster" | "point"
    let clusterId: Int64?
    let asset: DigitalAsset?
    let latitude: Double
    let longitude: Double
    let count: Int
    let memberIds: [UUID]
    
    var isCluster: Bool {
        kind == "cluster"
    }
    
    var displayTitle: String {
        if isCluster {
            return "\(count) artworks"
        } else {
            return asset?.name ?? "Artwork"
        }
    }
    
    /// Create from a cluster row
    static func fromCluster(clusterId: Int64, latitude: Double, longitude: Double, count: Int, memberIds: [UUID]) -> ClusterNode {
        ClusterNode(
            id: "cluster:\(clusterId)",
            kind: "cluster",
            clusterId: clusterId,
            asset: nil,
            latitude: latitude,
            longitude: longitude,
            count: count,
            memberIds: memberIds
        )
    }
    
    /// Create from a single asset
    static func fromAsset(_ asset: DigitalAsset) -> ClusterNode {
        ClusterNode(
            id: "asset:\(asset.id.uuidString)",
            kind: "point",
            clusterId: nil,
            asset: asset,
            latitude: asset.latitude ?? 0,
            longitude: asset.longitude ?? 0,
            count: 1,
            memberIds: [asset.id]
        )
    }
}

