//
//  StrokeBuilder.swift
//  Locolo
//
//  Turns a drawn 3D centerline into a smooth tube mesh (WS7). Produces both a
//  RealityKit MeshResource (for live preview) and raw geometry buffers (for the
//  ModelIO → USDZ export).
//

import Foundation
import RealityKit
import simd

/// Raw triangle geometry shared by the live preview and the USDZ exporter.
struct StrokeGeometry {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []
}

enum StrokeBuilder {
    /// Resample + lightly smooth a raw point list to uniform spacing so the
    /// tube doesn't kink where the hand jittered.
    static func smooth(_ points: [SIMD3<Float>], minSpacing: Float = 0.005) -> [SIMD3<Float>] {
        guard points.count > 2 else { return points }
        var out: [SIMD3<Float>] = [points[0]]
        for p in points.dropFirst() {
            if simd_distance(p, out.last!) >= minSpacing { out.append(p) }
        }
        guard out.count > 2 else { return out }
        // One moving-average pass.
        var smoothed = out
        for i in 1..<(out.count - 1) {
            smoothed[i] = (out[i - 1] + out[i] + out[i + 1]) / 3
        }
        return smoothed
    }

    /// Build a tube of `radius` with `sides` around a centerline using a stable
    /// parallel-transport frame (avoids twisting between rings).
    static func tube(centerline raw: [SIMD3<Float>], radius: Float = 0.01, sides: Int = 8) -> StrokeGeometry {
        let pts = smooth(raw)
        var geo = StrokeGeometry()
        guard pts.count >= 2 else { return geo }

        // Initial frame: pick an "up" that isn't parallel to the first tangent.
        var tangent = simd_normalize(pts[1] - pts[0])
        let reference = abs(tangent.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        var normal = simd_normalize(simd_cross(reference, tangent))
        var binormal = simd_cross(tangent, normal)

        var ringStartIndices: [Int] = []

        for i in 0..<pts.count {
            // Update the frame via parallel transport.
            if i > 0 {
                let newTangent = i < pts.count - 1
                    ? simd_normalize(pts[i + 1] - pts[i - 1])
                    : simd_normalize(pts[i] - pts[i - 1])
                let axis = simd_cross(tangent, newTangent)
                let axisLen = simd_length(axis)
                if axisLen > 1e-5 {
                    let angle = asin(min(1, axisLen))
                    let q = simd_quatf(angle: angle, axis: axis / axisLen)
                    normal = simd_normalize(q.act(normal))
                }
                tangent = newTangent
                binormal = simd_cross(tangent, normal)
            }

            ringStartIndices.append(geo.positions.count)
            for s in 0..<sides {
                let theta = 2 * Float.pi * Float(s) / Float(sides)
                let dir = simd_normalize(cos(theta) * normal + sin(theta) * binormal)
                geo.positions.append(pts[i] + dir * radius)
                geo.normals.append(dir)
            }
        }

        // Stitch consecutive rings into quads (two triangles each).
        for ring in 0..<(pts.count - 1) {
            let a = ringStartIndices[ring]
            let b = ringStartIndices[ring + 1]
            for s in 0..<sides {
                let sNext = (s + 1) % sides
                let i0 = UInt32(a + s)
                let i1 = UInt32(a + sNext)
                let i2 = UInt32(b + s)
                let i3 = UInt32(b + sNext)
                // (normal, binormal, tangent) is right-handed, so this order
                // gives counter-clockwise, outward-facing triangles.
                geo.indices.append(contentsOf: [i0, i1, i2, i1, i3, i2])
            }
        }

        addCap(to: &geo, center: pts[0], ringStart: ringStartIndices[0], sides: sides,
               outward: -simd_normalize(pts[1] - pts[0]), facesBackward: true)
        addCap(to: &geo, center: pts[pts.count - 1], ringStart: ringStartIndices[pts.count - 1], sides: sides,
               outward: simd_normalize(pts[pts.count - 1] - pts[pts.count - 2]), facesBackward: false)

        return geo
    }

    /// Closes a tube end with a triangle fan so strokes don't look hollow.
    private static func addCap(to geo: inout StrokeGeometry, center: SIMD3<Float>, ringStart: Int,
                               sides: Int, outward: SIMD3<Float>, facesBackward: Bool) {
        let centerIndex = UInt32(geo.positions.count)
        geo.positions.append(center)
        geo.normals.append(outward)
        for s in 0..<sides {
            let a = UInt32(ringStart + s)
            let b = UInt32(ringStart + (s + 1) % sides)
            // Ring order is counter-clockwise seen from +tangent.
            geo.indices.append(contentsOf: facesBackward ? [centerIndex, b, a] : [centerIndex, a, b])
        }
    }

    /// Merge several stroke geometries into one, offsetting indices.
    static func merge(_ geos: [StrokeGeometry]) -> StrokeGeometry {
        var out = StrokeGeometry()
        for g in geos {
            let offset = UInt32(out.positions.count)
            out.positions.append(contentsOf: g.positions)
            out.normals.append(contentsOf: g.normals)
            out.indices.append(contentsOf: g.indices.map { $0 + offset })
        }
        return out
    }

    /// A RealityKit mesh for live preview.
    static func meshResource(from geo: StrokeGeometry) -> MeshResource? {
        guard !geo.positions.isEmpty, !geo.indices.isEmpty else { return nil }
        var desc = MeshDescriptor(name: "stroke")
        desc.positions = MeshBuffers.Positions(geo.positions)
        desc.normals = MeshBuffers.Normals(geo.normals)
        desc.primitives = .triangles(geo.indices)
        return try? MeshResource.generate(from: [desc])
    }
}
