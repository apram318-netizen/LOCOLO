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
    @Published var useHandTracking = true {
        didSet { if isDrawing { endStroke() } }
    }
    @Published var statusHint = "Pinch and move to draw"

    /// Stroke appearance.
    @Published var strokeRadius: Float = 0.01
    @Published var strokeColor: UIColor = UIColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1) // Locolo violet
    @Published var brushStyle: BrushStyle = .tube

    /// Upper bound on total centerline points so the exported USDZ stays small.
    static let maxTotalPoints = 6000
    @Published private(set) var totalPoints = 0
    var isNearPointCap: Bool { totalPoints > Self.maxTotalPoints * 9 / 10 }

    weak var arView: ARView?

    private var anchor: AnchorEntity?
    private var committedGeometries: [StrokeGeometry] = []
    private var committedColors: [UIColor] = []
    private var committedPointCounts: [Int] = []
    private var committedEntities: [ModelEntity] = []
    private var currentPoints: [SIMD3<Float>] = []
    private var previewEntity: ModelEntity?

    private func material(for color: UIColor, style: BrushStyle) -> RealityKit.Material {
        switch style {
        case .neon:
            // Bright unlit + slight emissive feel via saturated colour.
            var c = color
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            c = UIColor(red: min(1, r * 1.25 + 0.1),
                        green: min(1, g * 1.25 + 0.1),
                        blue: min(1, b * 1.25 + 0.1),
                        alpha: 1)
            return UnlitMaterial(color: c)
        case .tube, .ribbon:
            return UnlitMaterial(color: color)
        }
    }

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
        guard totalPoints + currentPoints.count < Self.maxTotalPoints else {
            statusHint = "Canvas full — finish or undo a stroke"
            return
        }
        currentPoints.append(p)
        // Rebuilding the whole tube is O(n); thin out preview updates on long strokes.
        let every = currentPoints.count > 200 ? 6 : 2
        if currentPoints.count % every == 0 { updatePreview() }
    }

    func endStroke() {
        isDrawing = false
        defer { currentPoints.removeAll(); clearPreview() }
        guard currentPoints.count >= 2 else { return }

        let style = brushStyle
        let geo = StrokeBuilder.geometry(centerline: currentPoints, radius: strokeRadius, style: style)
        guard let mesh = StrokeBuilder.meshResource(from: geo) else { return }

        ensureAnchor()
        let entity = ModelEntity(mesh: mesh, materials: [material(for: strokeColor, style: style)])
        anchor?.addChild(entity)

        committedGeometries.append(geo)
        committedColors.append(strokeColor)
        committedPointCounts.append(currentPoints.count)
        committedEntities.append(entity)
        totalPoints += currentPoints.count
        strokeCount = committedEntities.count
        statusHint = isNearPointCap
            ? "Almost out of canvas — finish soon"
            : "Pinch to draw the next stroke"
    }

    func undo() {
        guard let entity = committedEntities.popLast() else { return }
        entity.removeFromParent()
        committedGeometries.removeLast()
        committedColors.removeLast()
        totalPoints -= committedPointCounts.popLast() ?? 0
        strokeCount = committedEntities.count
        ARHaptics.tick()
    }

    func clearAll() {
        committedEntities.forEach { $0.removeFromParent() }
        committedEntities.removeAll()
        committedGeometries.removeAll()
        committedColors.removeAll()
        committedPointCounts.removeAll()
        totalPoints = 0
        clearPreview()
        currentPoints.removeAll()
        strokeCount = 0
    }

    // MARK: Preview

    private func updatePreview() {
        guard currentPoints.count >= 2 else { return }
        let style = brushStyle
        let geo = StrokeBuilder.geometry(centerline: currentPoints, radius: strokeRadius, style: style)
        guard let mesh = StrokeBuilder.meshResource(from: geo) else { return }
        ensureAnchor()
        let mats = [material(for: strokeColor, style: style)]
        if let previewEntity {
            previewEntity.model?.mesh = mesh
            previewEntity.model?.materials = mats
        } else {
            let e = ModelEntity(mesh: mesh, materials: mats)
            anchor?.addChild(e)
            previewEntity = e
        }
    }

    private func clearPreview() {
        previewEntity?.removeFromParent()
        previewEntity = nil
    }

    // MARK: Export

    /// Export all committed strokes (each keeping its colour) to a temporary .usdz.
    func exportUSDZ() throws -> URL {
        let strokes = zip(committedGeometries, committedColors).map {
            USDZExporter.Stroke(geometry: $0, color: $1)
        }
        return try USDZExporter.export(strokes, name: "locolo-drawing")
    }
}
