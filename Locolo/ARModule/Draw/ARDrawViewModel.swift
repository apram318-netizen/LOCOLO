//
//  ARDrawViewModel.swift
//  Locolo
//
//  Drives air-drawing (WS7): accumulates 3D points into strokes, keeps a live
//  RealityKit preview, supports undo, and exports the finished drawing to USDZ
//  so it can flow through the normal create/post pipeline.
//

import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

@MainActor
final class ARDrawViewModel: ObservableObject {
    @Published var strokeCount = 0
    @Published var isDrawing = false
    @Published var useHandTracking = true
    @Published var statusHint = "Pinch and move to draw"

    /// Stroke appearance.
    var strokeRadius: Float = 0.01
    var strokeColor: UIColor = UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1) // Locolo violet

    weak var arView: ARView?

    private var anchor: AnchorEntity?
    private var committedGeometries: [StrokeGeometry] = []
    private var committedEntities: [ModelEntity] = []
    private var currentPoints: [SIMD3<Float>] = []
    private var previewEntity: ModelEntity?

    var canUndo: Bool { !committedEntities.isEmpty }
    var hasContent: Bool { !committedGeometries.isEmpty }

    // MARK: Scene setup

    private func ensureAnchor() {
        guard anchor == nil, let arView else { return }
        // Positions are absolute world coordinates, so anchor at world origin.
        let a = AnchorEntity(world: .zero)
        arView.scene.addAnchor(a)
        anchor = a
    }

    // MARK: Stroke lifecycle

    func beginStroke() {
        currentPoints.removeAll()
        isDrawing = true
        statusHint = "Drawing…"
    }

    func addPoint(_ p: SIMD3<Float>) {
        // Skip near-duplicate points to bound density.
        if let last = currentPoints.last, simd_distance(last, p) < 0.004 { return }
        currentPoints.append(p)
        if currentPoints.count % 2 == 0 { updatePreview() }
    }

    func endStroke() {
        isDrawing = false
        defer { currentPoints.removeAll(); clearPreview() }
        guard currentPoints.count >= 2 else { return }

        let geo = StrokeBuilder.tube(centerline: currentPoints, radius: strokeRadius)
        guard let mesh = StrokeBuilder.meshResource(from: geo) else { return }

        ensureAnchor()
        let entity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: strokeColor)])
        anchor?.addChild(entity)

        committedGeometries.append(geo)
        committedEntities.append(entity)
        strokeCount = committedEntities.count
        statusHint = "Pinch to draw the next stroke"
    }

    func undo() {
        guard let entity = committedEntities.popLast() else { return }
        entity.removeFromParent()
        committedGeometries.removeLast()
        strokeCount = committedEntities.count
        ARHaptics.tick()
    }

    func clearAll() {
        committedEntities.forEach { $0.removeFromParent() }
        committedEntities.removeAll()
        committedGeometries.removeAll()
        clearPreview()
        currentPoints.removeAll()
        strokeCount = 0
    }

    // MARK: Preview

    private func updatePreview() {
        guard currentPoints.count >= 2 else { return }
        let geo = StrokeBuilder.tube(centerline: currentPoints, radius: strokeRadius)
        guard let mesh = StrokeBuilder.meshResource(from: geo) else { return }
        ensureAnchor()
        if let previewEntity {
            previewEntity.model?.mesh = mesh
        } else {
            let e = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: strokeColor)])
            anchor?.addChild(e)
            previewEntity = e
        }
    }

    private func clearPreview() {
        previewEntity?.removeFromParent()
        previewEntity = nil
    }

    // MARK: Export

    /// Merge all committed strokes and export to a temporary .usdz.
    func exportUSDZ() throws -> URL {
        let merged = StrokeBuilder.merge(committedGeometries)
        return try USDZExporter.export(merged, name: "locolo-drawing")
    }
}
