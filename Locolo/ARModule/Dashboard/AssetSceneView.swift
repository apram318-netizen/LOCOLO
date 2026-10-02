//
//  AssetSceneView.swift
//  Locolo
//
//  Interactive 3D preview for an asset (detail sheet hero, settings sheet).
//
//  V3 rewrite (feedback: "too zoomed in", "black background"):
//  * The SceneKit view is transparent; the backdrop is a SwiftUI aurora
//    (`AssetStageBackground`) tinted from the asset's thumbnail, so every
//    asset gets its own colourway instead of a black void.
//  * The camera is FITTED to the model's bounding sphere with padding, so
//    tall, wide and tiny models all sit fully in frame.
//  * Drag to orbit, pinch to zoom (clamped), double-tap to reset; a slow
//    turntable spin runs until the user touches it.
//  * Models come from MediaCache (no re-download per open), with a progress
//    ring while loading and a friendly fallback if the file can't be read.
//

import Foundation
import SwiftUI
import SceneKit
import UIKit

struct AssetSceneView: View {
    let asset: DigitalAsset
    /// Extra breathing room around the model (1 = tight fit).
    var framing: Float = 1.45

    @State private var phase: LoadPhase = .loading
    @State private var tint: [Color] = AssetStageBackground.defaultPalette

    enum LoadPhase: Equatable { case loading, ready, failed }

    var body: some View {
        ZStack {
            AssetStageBackground(palette: tint)

            AssetSceneRepresentable(asset: asset, framing: framing, phase: $phase)

            switch phase {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Loading 3D model…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .transition(.opacity)
            case .failed:
                VStack(spacing: 10) {
                    AssetThumbnailView(asset: asset, cornerRadius: 18)
                        .frame(width: 160, height: 160)
                        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    Text("3D preview unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            case .ready:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .task(id: asset.id) {
            if let colors = await AssetStageBackground.palette(for: asset) {
                withAnimation(.easeInOut(duration: 0.6)) { tint = colors }
            }
        }
    }
}

// MARK: - Backdrop

/// Soft studio backdrop: a deep gradient, two drifting colour blooms taken
/// from the asset's thumbnail, a horizon glow and a floor reflection.
struct AssetStageBackground: View {
    var palette: [Color]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    static let defaultPalette: [Color] = [Color(hex: "8B5CF6"), Color(hex: "EC4899"), Color(hex: "22D3EE")]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(hex: "120B24"), Color(hex: "1C1236"), Color(hex: "0B0716")],
                               startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(palette[0].opacity(0.55))
                    .frame(width: w * 0.9)
                    .blur(radius: 70)
                    .offset(x: drift ? -w * 0.22 : -w * 0.32, y: -h * 0.18)
                Circle()
                    .fill(palette[min(1, palette.count - 1)].opacity(0.42))
                    .frame(width: w * 0.8)
                    .blur(radius: 80)
                    .offset(x: drift ? w * 0.30 : w * 0.20, y: h * 0.02)
                Ellipse()
                    .fill(palette[min(2, palette.count - 1)].opacity(0.30))
                    .frame(width: w * 1.1, height: h * 0.22)
                    .blur(radius: 40)
                    .offset(y: h * 0.36)
                // Floor: a faint perspective grid fading into the horizon.
                FloorGrid()
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
                    .frame(height: h * 0.34)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .mask(LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom))
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }

    /// Two-to-three dominant colours from the asset's thumbnail.
    static func palette(for asset: DigitalAsset) async -> [Color]? {
        let image: UIImage?
        if let s = asset.thumbUrl, let url = URL(string: s),
           let (data, _) = try? await URLSession.shared.data(from: url) {
            image = UIImage(data: data)
        } else {
            image = await AssetThumbnailGenerator.thumbnail(for: asset)
        }
        guard let image else { return nil }
        let colors = image.locoloDominantColors(count: 3)
        return colors.isEmpty ? nil : colors.map { Color(uiColor: $0.locoloVivid()) }
    }
}

private struct FloorGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let vanish = CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
        for i in -8...8 {
            let x = rect.midX + CGFloat(i) * rect.width / 8
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: vanish)
        }
        for i in 1...6 {
            let t = pow(CGFloat(i) / 6, 1.8)
            let y = rect.minY + rect.height * t
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}

// MARK: - SceneKit

private struct AssetSceneRepresentable: UIViewRepresentable {
    let asset: DigitalAsset
    let framing: Float
    @Binding var phase: AssetSceneView.LoadPhase

    func makeCoordinator() -> Coordinator { Coordinator(phase: $phase) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false   // custom orbit below: clamped + resettable

        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        // Image-based lighting gives PBR models real reflections instead of
        // the flat, dim look of a few omni lights.
        scene.lightingEnvironment.contents = Self.studioEnvironment()
        scene.lightingEnvironment.intensity = 1.4
        view.scene = scene

        context.coordinator.install(in: view, framing: framing)
        context.coordinator.load(asset: asset)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.cancel()
    }

    /// A soft gradient "studio" used as the lighting environment.
    private static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 256, height: 128)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 1.0, alpha: 1).cgColor,
                          UIColor(white: 0.55, alpha: 1).cgColor,
                          UIColor(white: 0.18, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    final class Coordinator: NSObject {
        private var phase: Binding<AssetSceneView.LoadPhase>
        private weak var view: SCNView?
        private let pivot = SCNNode()        // yaw
        private let tilt = SCNNode()         // pitch
        private let cameraNode = SCNNode()
        private var framing: Float = 1.45
        private var fitDistance: Float = 4
        private var distance: Float = 4
        private var yaw: Float = 0
        private var pitch: Float = -0.12
        private var loadTask: Task<Void, Never>?

        init(phase: Binding<AssetSceneView.LoadPhase>) {
            self.phase = phase
        }

        func install(in view: SCNView, framing: Float) {
            self.view = view
            self.framing = framing
            guard let root = view.scene?.rootNode else { return }

            let camera = SCNCamera()
            camera.fieldOfView = 38
            camera.zNear = 0.01
            camera.zFar = 200
            camera.wantsHDR = true
            camera.bloomIntensity = 0.25
            camera.bloomThreshold = 0.9
            cameraNode.camera = camera
            root.addChildNode(pivot)
            pivot.addChildNode(tilt)
            tilt.addChildNode(cameraNode)
            view.pointOfView = cameraNode

            // Key + rim lights on top of the environment.
            let key = SCNLight()
            key.type = .directional
            key.intensity = 900
            key.castsShadow = true
            key.shadowMode = .deferred
            key.shadowColor = UIColor.black.withAlphaComponent(0.45)
            key.shadowRadius = 8
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
            root.addChildNode(keyNode)

            let rim = SCNLight()
            rim.type = .directional
            rim.intensity = 450
            rim.color = UIColor(red: 0.75, green: 0.65, blue: 1.0, alpha: 1)
            let rimNode = SCNNode()
            rimNode.light = rim
            rimNode.eulerAngles = SCNVector3(-Float.pi / 6, Float.pi, 0)
            root.addChildNode(rimNode)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 180
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            root.addChildNode(ambientNode)

            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(reset))
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
            applyCamera()
        }

        func cancel() { loadTask?.cancel() }

        func load(asset: DigitalAsset) {
            guard let remote = URL(string: asset.fileUrl) else { fail(); return }
            loadTask = Task { [weak self] in
                let local: URL
                if let cached = MediaCache.shared.localURL(forRemoteURL: remote) {
                    local = cached
                } else {
                    guard let (data, _) = try? await URLSession.shared.data(from: remote),
                          let stored = MediaCache.shared.store(data: data, for: remote, fileExtension: "usdz")
                    else { await MainActor.run { self?.fail() }; return }
                    local = stored
                }
                guard !Task.isCancelled else { return }
                // SCNScene(url:) parses off the main thread.
                let modelScene = try? SCNScene(url: local, options: [.checkConsistency: false])
                await MainActor.run { self?.present(modelScene) }
            }
        }

        private func fail() {
            phase.wrappedValue = .failed
        }

        @MainActor
        private func present(_ modelScene: SCNScene?) {
            guard let modelScene, let root = view?.scene?.rootNode else { fail(); return }
            let container = SCNNode()
            for child in modelScene.rootNode.childNodes { container.addChildNode(child) }

            // Fit: centre on the bounding box, rest on the floor, scale so the
            // bounding sphere has radius 1 → camera distance is model-agnostic.
            let (minB, maxB) = container.boundingBox
            let size = SCNVector3(maxB.x - minB.x, maxB.y - minB.y, maxB.z - minB.z)
            let radius = max(0.0001, sqrt(size.x * size.x + size.y * size.y + size.z * size.z) / 2)
            let scale = 1 / radius
            container.scale = SCNVector3(scale, scale, scale)
            container.position = SCNVector3(-(minB.x + size.x / 2) * scale,
                                            -(minB.y + size.y / 2) * scale,
                                            -(minB.z + size.z / 2) * scale)

            let floorY = -size.y / 2 * scale
            root.addChildNode(Self.shadowCatcher(at: floorY))

            let turntable = SCNNode()
            turntable.name = "turntable"
            turntable.addChildNode(container)
            root.addChildNode(turntable)

            // Distance so a unit sphere fills the vertical FOV, plus framing.
            let fov = Float((cameraNode.camera?.fieldOfView ?? 38) * .pi / 180)
            fitDistance = (1 / sin(fov / 2)) * framing
            distance = fitDistance
            applyCamera()

            container.opacity = 0
            container.runAction(.fadeIn(duration: 0.5))
            if !UIAccessibility.isReduceMotionEnabled {
                turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)), forKey: "spin")
            }
            // Play any embedded animation so animated drops feel alive.
            container.enumerateChildNodes { node, _ in
                for key in node.animationKeys { node.animationPlayer(forKey: key)?.play() }
            }
            view?.rendersContinuously = true
            phase.wrappedValue = .ready
        }

        /// Invisible floor that only receives the model's shadow.
        private static func shadowCatcher(at y: Float) -> SCNNode {
            let plane = SCNFloor()
            plane.reflectivity = 0
            let m = SCNMaterial()
            m.lightingModel = .shadowOnly
            m.diffuse.contents = UIColor.clear
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.position = SCNVector3(0, y, 0)
            return node
        }

        private func applyCamera() {
            pivot.eulerAngles.y = yaw
            tilt.eulerAngles.x = pitch
            cameraNode.position = SCNVector3(0, 0, distance)
        }

        private func stopSpin() {
            view?.scene?.rootNode.childNode(withName: "turntable", recursively: false)?
                .removeAction(forKey: "spin")
        }

        @objc private func pan(_ g: UIPanGestureRecognizer) {
            stopSpin()
            let t = g.translation(in: g.view)
            g.setTranslation(.zero, in: g.view)
            yaw -= Float(t.x) * 0.008
            pitch = min(0.35, max(-1.1, pitch - Float(t.y) * 0.006))
            applyCamera()
        }

        @objc private func pinch(_ g: UIPinchGestureRecognizer) {
            stopSpin()
            distance = min(fitDistance * 2.2, max(fitDistance * 0.45, distance / Float(g.scale)))
            g.scale = 1
            applyCamera()
        }

        @objc private func reset() {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.45
            yaw = 0
            pitch = -0.12
            distance = fitDistance
            applyCamera()
            SCNTransaction.commit()
        }
    }
}

// MARK: - Colour helpers

extension UIImage {
    /// Cheap dominant colours: downsample to 24×24 and bucket hues.
    func locoloDominantColors(count: Int) -> [UIColor] {
        let side = 24
        guard let cg = cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var buckets: [Int: (r: CGFloat, g: CGFloat, b: CGFloat, n: CGFloat)] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255, g = CGFloat(pixels[i + 1]) / 255, b = CGFloat(pixels[i + 2]) / 255
            let c = UIColor(red: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
            guard s > 0.18, v > 0.18 else { continue }   // skip greys / near-black
            let key = Int(h * 12)
            let cur = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (cur.r + r, cur.g + g, cur.b + b, cur.n + 1)
        }
        return buckets.values.sorted { $0.n > $1.n }.prefix(count).map {
            UIColor(red: $0.r / $0.n, green: $0.g / $0.n, blue: $0.b / $0.n, alpha: 1)
        }
    }
}

extension UIColor {
    /// Push saturation/brightness up so blooms glow rather than look muddy.
    func locoloVivid() -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return UIColor(hue: h, saturation: min(1, max(0.55, s * 1.2)), brightness: min(1, max(0.7, v * 1.15)), alpha: 1)
    }
}
