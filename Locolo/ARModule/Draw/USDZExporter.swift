//
//  USDZExporter.swift
//  Locolo
//
//  Exports drawn strokes to a .usdz file (WS7), so a hand-drawing flows through
//  the exact same upload/create pipeline as an uploaded model.
//
//  ModelIO cannot write .usdz on iOS (MDLAsset.canExportFileExtension("usdz")
//  is false there), so the scene is built and written with SceneKit, which
//  supports .usdz export on iOS 13+.
//

import Foundation
import SceneKit
import UIKit
import simd

enum USDZExporter {
    enum ExportError: Error { case emptyGeometry, exportFailed }

    struct Stroke {
        let geometry: StrokeGeometry
        let color: UIColor
    }

    /// Writes the strokes to a temporary .usdz and returns its URL. Geometry is
    /// re-centred so the drawing's footprint is centred on the origin and its
    /// lowest point rests at y = 0 — the viewer anchors the model at its GPS
    /// point on the ground, so world-space capture coordinates would float
    /// the drawing off to wherever the artist happened to be standing.
    static func export(_ strokes: [Stroke], name: String = "drawing") throws -> URL {
        let drawable = strokes.filter { !$0.geometry.positions.isEmpty && $0.geometry.indices.count >= 3 }
        guard !drawable.isEmpty else { throw ExportError.emptyGeometry }

        let offset = groundCentreOffset(drawable.flatMap(\.geometry.positions))

        let scene = SCNScene()
        for stroke in drawable {
            scene.rootNode.addChildNode(node(for: stroke, offset: offset))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).usdz")

        let ok = scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard ok, size > 0 else { throw ExportError.exportFailed }
        return url
    }

    // MARK: - Helpers

    private static func groundCentreOffset(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in points {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        return SIMD3<Float>((lo.x + hi.x) / 2, lo.y, (lo.z + hi.z) / 2)
    }

    private static func node(for stroke: Stroke, offset: SIMD3<Float>) -> SCNNode {
        let geo = stroke.geometry
        let vertices = geo.positions.map { p -> SCNVector3 in
            let q = p - offset
            return SCNVector3(q.x, q.y, q.z)
        }
        let normals = geo.positions.indices.map { i -> SCNVector3 in
            let n = i < geo.normals.count ? geo.normals[i] : SIMD3<Float>(0, 1, 0)
            return SCNVector3(n.x, n.y, n.z)
        }

        let element = SCNGeometryElement(indices: geo.indices, primitiveType: .triangles)
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: [element]
        )

        // Emission keeps the strokes glowing like the unlit live preview while
        // still exporting as a standard PBR material.
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = stroke.color
        material.emission.contents = stroke.color.withAlphaComponent(0.6)
        material.roughness.contents = 0.4
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }
}
