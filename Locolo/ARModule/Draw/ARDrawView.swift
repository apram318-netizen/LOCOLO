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
        /// Vision is too slow for the main thread; one frame in flight at a
        /// time so we never queue up (and retain) stale camera buffers.
        private let visionQueue = DispatchQueue(label: "com.locolo.draw.vision", qos: .userInteractive)
        private var isProcessing = false
        /// Consecutive frames without a confident hand while pinching.
        private var missedFrames = 0
        private let maxMissedFrames = 6

        init(vm: ARDrawViewModel) { self.vm = vm }

        // MARK: Vision hand tracking

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // No delegateQueue is set, so ARKit calls us on the main thread.
            let wantsHands = MainActor.assumeIsolated { vm.useHandTracking }
            guard wantsHands, !isProcessing else { return }
            isProcessing = true

            let pixelBuffer = frame.capturedImage
            visionQueue.async { [weak self] in
                guard let self else { return }
                let result = self.handTracker.process(pixelBuffer: pixelBuffer)
                let pinchingBeforeLoss = self.handTracker.isPinching
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.isProcessing = false
                        guard self.vm.useHandTracking else { return }
                        if let result {
                            self.missedFrames = 0
                            self.handleInput(normalizedPoint: result.indexTip,
                                             isActive: result.isPinching,
                                             changed: result.pinchChanged)
                        } else if pinchingBeforeLoss {
                            // Hand left the frame mid-stroke: close the stroke
                            // instead of leaving it dangling open.
                            self.missedFrames += 1
                            if self.missedFrames >= self.maxMissedFrames {
                                self.missedFrames = 0
                                self.visionQueue.async { self.handTracker.reset() }
                                self.vm.endStroke()
                            }
                        }
                    }
                }
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
            guard isActive,
                  let screen = screenPoint(fromVisionNormalized: normalizedPoint, in: view)
            else { return }
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

        /// Maps a Vision point to ARView coordinates.
        ///
        /// Vision ran with orientation `.right`, so `p` is normalized in the
        /// upright (portrait) image with a bottom-left origin. Undo that to get
        /// normalized coordinates in the raw landscape capture (top-left origin),
        /// then let ARKit's display transform apply the rotation and the
        /// aspect-fill crop the ARView uses on screen.
        @MainActor
        private func screenPoint(fromVisionNormalized p: CGPoint, in view: ARView) -> CGPoint? {
            guard let frame = view.session.currentFrame else { return nil }
            let size = view.bounds.size
            let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            let raw = CGPoint(x: 1 - p.y, y: 1 - p.x)
            let normalized = raw.applying(frame.displayTransform(for: orientation, viewportSize: size))
            return CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
        }
    }
}
