//
//  USDZExporter.swift
//  Locolo
//
//  Exports drawn stroke geometry to a .usdz file via ModelIO (WS7), so a
//  hand-drawing can flow through the exact same upload/create pipeline as an
//  uploaded model.
//

import Foundation
import ModelIO
import Metal
import simd

enum USDZExporter {
    enum ExportError: Error { case emptyGeometry, noBuffer, exportFailed }

    /// Writes the merged geometry to a temporary .usdz and returns its URL.
    static func export(_ geo: StrokeGeometry, name: String = "drawing") throws -> URL {
        guard !geo.positions.isEmpty, geo.indices.count >= 3 else { throw ExportError.emptyGeometry }

        let allocator = MDLMeshBufferDataAllocator()

        // Interleave position + normal into a single vertex buffer.
        var vertexData = Data()
        vertexData.reserveCapacity(geo.positions.count * MemoryLayout<Float>.size * 6)
        for i in 0..<geo.positions.count {
            var p = geo.positions[i]
            var n = i < geo.normals.count ? geo.normals[i] : SIMD3<Float>(0, 1, 0)
            withUnsafeBytes(of: &p) { vertexData.append(contentsOf: $0) }
            withUnsafeBytes(of: &n) { vertexData.append(contentsOf: $0) }
        }

        var indexData = Data()
        indexData.reserveCapacity(geo.indices.count * MemoryLayout<UInt32>.size)
        for var idx in geo.indices {
            withUnsafeBytes(of: &idx) { indexData.append(contentsOf: $0) }
        }

        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: geo.indices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: makeMaterial()
        )

        // Vertex descriptor: position (float3) then normal (float3), stride 24.
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal, format: .float3,
            offset: MemoryLayout<SIMD3<Float>>.stride, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride * 2)

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: geo.positions.count,
            descriptor: descriptor,
            submeshes: [submesh]
        )

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString).usdz")

        guard MDLAsset.canExportFileExtension("usdz") else { throw ExportError.exportFailed }
        try asset.export(to: url)
        return url
    }

    private static func makeMaterial() -> MDLMaterial {
        let scatter = MDLScatteringFunction()
        let material = MDLMaterial(name: "strokeMaterial", scatteringFunction: scatter)
        let color = MDLMaterialProperty(
            name: "baseColor", semantic: .baseColor,
            float3: SIMD3<Float>(0.55, 0.36, 0.96)) // Locolo violet
        material.setProperty(color)
        return material
    }
}
