//
//  ARPlacementView.swift
//  Locolo
//
//  Created by Apramjot Singh on 5/11/2025.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARPlacementView: UIViewRepresentable {
    let modelURL: URL
    let vm: ARCreateViewModel   // ViewModel reference for navigation + data persistence

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        // Must stay false: an automatic world config would drop the
        // .gravityAndHeading alignment the saved quaternion depends on.
        arView.automaticallyConfigureSession = false

        // --- Configure AR Session ---
        // North-aligned world so captured orientation is expressed relative to
        // true north (-Z = north, +X = east). This is the frame the viewer
        // replays in, so the asset faces the same real-world direction. (WS2)
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
        LocoloLog.debug(LocoloLog.ar, "placement session started")

        // --- Add Coaching Overlay (helps with localization) ---
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        // --- Debug Options ---
        arView.debugOptions = [.showFeaturePoints]

        // --- Load the model asynchronously ---
        Task {
            do {
                let localURL = try await context.coordinator.downloadToLocal(modelURL)
                LocoloLog.debug(LocoloLog.ar, "model downloaded")

                context.coordinator.cancellable = ModelEntity.loadModelAsync(contentsOf: localURL)
                    .sink(
                        receiveCompletion: { completion in
                            if case let .failure(error) = completion {
                                LocoloLog.ar.error("model load failed: \(error.localizedDescription, privacy: .public)")
                            }
                        },
                        receiveValue: { entity in
                            LocoloLog.debug(LocoloLog.ar, "model entity loaded")
                            entity.generateCollisionShapes(recursive: true)
                            // No .translation: the saved position is the user's
                            // GPS point, so letting them drag the model would be
                            // dishonest (the drag is discarded). Rotate/scale only. (WS2)
                            arView.installGestures([.rotation, .scale], for: entity)

                            let anchor = AnchorEntity(plane: .horizontal)
                            // Soft contact shadow so grounding is easier to judge.
                            let shadow = ModelEntity(
                                mesh: .generateCylinder(height: 0.002, radius: 0.18),
                                materials: [UnlitMaterial(color: UIColor.black.withAlphaComponent(0.28))])
                            shadow.position = [0, 0.001, 0]
                            shadow.name = "placementShadow"
                            anchor.addChild(shadow)
                            anchor.addChild(entity)
                            arView.scene.addAnchor(anchor)

                            context.coordinator.entity = entity
                            context.coordinator.shadowEntity = shadow
                            context.coordinator.baseScale = entity.scale
                            LocoloLog.debug(LocoloLog.ar, "entity anchored")
                        }
                    )
            } catch {
                LocoloLog.ar.error("download/load failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // --- Long-Press Gesture for Placement Confirmation ---
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.confirm)
        )
        longPress.minimumPressDuration = 0.6
        longPress.delegate = context.coordinator
        arView.addGestureRecognizer(longPress)
        LocoloLog.debug(LocoloLog.ar, "long-press gesture installed")

        // --- Floating Guidance Label ---
        let label = UILabel()
        label.text = "🪄 Move your device to detect a surface\nTap & hold to confirm placement"
        label.textAlignment = .center
        label.textColor = .white
        label.numberOfLines = 2
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        arView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: arView.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            label.widthAnchor.constraint(lessThanOrEqualTo: arView.widthAnchor, multiplier: 0.9)
        ])

        // True-size reset control (placement finesse).
        let trueSize = UIButton(type: .system)
        trueSize.setTitle(" True size ", for: .normal)
        trueSize.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        trueSize.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        trueSize.setTitleColor(.white, for: .normal)
        trueSize.layer.cornerRadius = 8
        trueSize.translatesAutoresizingMaskIntoConstraints = false
        trueSize.addTarget(context.coordinator, action: #selector(Coordinator.resetTrueSize), for: .touchUpInside)
        arView.addSubview(trueSize)
        NSLayoutConstraint.activate([
            trueSize.trailingAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            trueSize.topAnchor.constraint(equalTo: arView.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])

        // Keep view model + guidance label references inside coordinator
        context.coordinator.vm = vm
        context.coordinator.guidanceLabel = label
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var entity: ModelEntity?
        var shadowEntity: ModelEntity?
        var baseScale: SIMD3<Float> = .one
        var cancellable: AnyCancellable?
        weak var vm: ARCreateViewModel?
        weak var guidanceLabel: UILabel?

        @objc func resetTrueSize() {
            guard let entity else { return }
            entity.scale = baseScale
            // Softly resize the contact shadow with the model.
            if let shadowEntity {
                let avg = (baseScale.x + baseScale.z) * 0.5
                shadowEntity.scale = [max(0.4, avg), 1, max(0.4, avg)]
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guidanceLabel?.text = "Reset to true size — rotate/scale, then hold to place"
        }

        // Allow gestures to coexist
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // Handle long-press confirmation
        @objc func confirm(_ sender: UILongPressGestureRecognizer) {
            guard sender.state == .began else { return }
            LocoloLog.debug(LocoloLog.ar, "placement long-press")

            guard let entity = entity else {
                LocoloLog.ar.error("placement confirm with no entity")
                return
            }

            // The compass must be reliable — otherwise the captured heading
            // (and thus this asset's facing direction for every future viewer)
            // is wrong. Block placement and prompt a figure-8 calibration. (WS2)
            if let vm = vm, !vm.hasReliableHeading {
                guidanceLabel?.text = "🧭 Calibrate compass\nMove your phone in a figure-8, then hold to place"
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }

            // Capture orientation & scale in WORLD space (relative to the
            // north-aligned session), not relative to the plane anchor. (WS2)
            let worldRotation = entity.orientation(relativeTo: nil)
            let worldScale = entity.scale(relativeTo: nil)

            DispatchQueue.main.async {
                LocoloLog.debug(LocoloLog.ar, "placement confirmed")
                self.vm?.setPlacement(rotationWorld: worldRotation, scale: worldScale)

                // Push "details" destination after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.vm?.navPath.append("details")
                }
            }
        }

        // Download remote USDZ to local temp file
        func downloadToLocal(_ remoteURL: URL) async throws -> URL {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(remoteURL.lastPathComponent)
            try data.write(to: localURL)
            return localURL
        }
    }
}
