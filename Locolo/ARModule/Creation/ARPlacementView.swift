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
        print(" AR session started")

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
                print(" Downloaded model to:", localURL.lastPathComponent)

                context.coordinator.cancellable = ModelEntity.loadModelAsync(contentsOf: localURL)
                    .sink(
                        receiveCompletion: { completion in
                            if case let .failure(error) = completion {
                                print(" Model load failed:", error.localizedDescription)
                            }
                        },
                        receiveValue: { entity in
                            print(" Model entity loaded")
                            entity.generateCollisionShapes(recursive: true)
                            // No .translation: the saved position is the user's
                            // GPS point, so letting them drag the model would be
                            // dishonest (the drag is discarded). Rotate/scale only. (WS2)
                            arView.installGestures([.rotation, .scale], for: entity)

                            let anchor = AnchorEntity(plane: .horizontal)
                            anchor.addChild(entity)
                            arView.scene.addAnchor(anchor)

                            context.coordinator.entity = entity
                            print("📍 Entity anchored and interactive")
                        }
                    )
            } catch {
                print(" Download or load failed:", error)
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
        print(" Long-press gesture added")

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
        var cancellable: AnyCancellable?
        weak var vm: ARCreateViewModel?
        weak var guidanceLabel: UILabel?

        // Allow gestures to coexist
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // Handle long-press confirmation
        @objc func confirm(_ sender: UILongPressGestureRecognizer) {
            guard sender.state == .began else { return }
            print(" [Coordinator] Long press detected")

            guard let entity = entity else {
                print(" [Coordinator] No entity to place")
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
                print(" [Coordinator] Saving world-space placement to ViewModel & navigating")
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
