//
//  ARDrawView.swift
//  Locolo
//
//  RealityKit host for air-drawing (WS7). Runs Vision hand-pose detection on
//  the AR camera feed to drive a pinch-to-draw interaction, with a touch-drag
//  fallback. Projects the input point to a fixed depth in front of the camera.
//

import SwiftUI
import RealityKit
import ARKit

struct ARDrawView: UIViewRepresentable {
    let vm: ARDrawViewModel

    /// Depth in metres in front of the camera where strokes are drawn.
    private let drawDepth: Float = 0.4

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        vm.arView = arView

        #if !targetEnvironment(simulator)
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading   // share the north frame (WS2/WS7)
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        arView.session.delegate = context.coordinator
        #endif

        // Touch fallback: drag to draw when hands aren't tracked.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(pan)

        context.coordinator.arView = arView
        context.coordinator.drawDepth = drawDepth
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSessionDelegate {
        let vm: ARDrawViewModel
        weak var arView: ARView?
        var drawDepth: Float = 0.4

        private let handTracker = HandTracker()
        private var frameCount = 0

        init(vm: ARDrawViewModel) { self.vm = vm }

        // MARK: Vision hand tracking

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            frameCount += 1
            guard frameCount % 2 == 0 else { return }   // throttle to every other frame

            let pixelBuffer = frame.capturedImage
            guard let result = handTracker.process(pixelBuffer: pixelBuffer) else { return }

            Task { @MainActor in
                guard self.vm.useHandTracking else { return }   // main-actor read
                self.handleInput(normalizedPoint: result.indexTip,
                                 isActive: result.isPinching,
                                 changed: result.pinchChanged)
            }
        }

        // MARK: Touch fallback

        @MainActor @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard !vm.useHandTracking, let view = gesture.view else { return }
            let p = gesture.location(in: view)
            switch gesture.state {
            case .began:
                vm.beginStroke()
                addProjectedPoint(screenPoint: p)
            case .changed:
                addProjectedPoint(screenPoint: p)
            case .ended, .cancelled, .failed:
                vm.endStroke()
            default: break
            }
        }

        // MARK: Input → 3D

        @MainActor
        private func handleInput(normalizedPoint: CGPoint, isActive: Bool, changed: Bool) {
            guard let view = arView else { return }
            if changed {
                if isActive { vm.beginStroke() } else { vm.endStroke() }
            }
            guard isActive else { return }
            let screen = screenPoint(fromVisionNormalized: normalizedPoint, viewSize: view.bounds.size)
            addProjectedPoint(screenPoint: screen)
        }

        @MainActor
        private func addProjectedPoint(screenPoint: CGPoint) {
            guard let view = arView else { return }
            let world = projectToFixedDepth(screenPoint: screenPoint, in: view)
            vm.addPoint(world)
        }

        /// A point `drawDepth` metres in front of the camera along the ray
        /// through the screen point (more stable than raycasting for air-drawing).
        @MainActor
        private func projectToFixedDepth(screenPoint: CGPoint, in view: ARView) -> SIMD3<Float> {
            if let ray = view.ray(through: screenPoint) {
                return ray.origin + ray.direction * drawDepth
            }
            // Fallback: straight ahead of the camera.
            if let cam = view.session.currentFrame?.camera {
                let t = cam.transform
                let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
                let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                return origin + forward * drawDepth
            }
            return .zero
        }

        /// Maps a Vision normalized point (origin bottom-left, camera oriented
        /// `.right`) to ARView coordinates. Approximate — tune on device.
        private func screenPoint(fromVisionNormalized p: CGPoint, viewSize: CGSize) -> CGPoint {
            // For a back camera in portrait (.right), Vision's x maps to vertical
            // and y to horizontal; y is flipped for UIKit's top-left origin.
            let x = p.y * viewSize.width
            let y = p.x * viewSize.height
            return CGPoint(x: x, y: y)
        }
    }
}
